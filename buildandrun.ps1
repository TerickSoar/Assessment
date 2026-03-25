#!/usr/bin/env pwsh
<#
.SYNOPSIS
Build and run the Hello World application locally in Kubernetes

.DESCRIPTION
This script:
1. Builds the Docker image
2. Builds Helm dependencies
3. Installs the Helm chart to local Kubernetes
4. Sets up port-forwarding
5. Displays access information

.PARAMETER ImageTag
The Docker image tag to use (default: latest)

.PARAMETER Namespace
The Kubernetes namespace to deploy to (default: default)

.PARAMETER Port
The local port to forward to (default: 8081)

.EXAMPLE
./buildandrun.ps1
./buildandrun.ps1 -ImageTag v1.0 -Namespace hello-world
#>

param(
    [string]$ImageTag = "",
    [string]$Namespace = "default",
    [int]$Port = 8081
)

# Get git short SHA if no tag provided
if (-not $ImageTag) {
    try {
        $ImageTag = git rev-parse --short HEAD
        if ($LASTEXITCODE -ne 0) {
            $ImageTag = "latest"
        }
    }
    catch {
        $ImageTag = "latest"
    }
}

# Color output functions
function Write-Success {
    param([string]$Message)
    Write-Host "$Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "$Message" -ForegroundColor Cyan
}

function Write-Error {
    param([string]$Message)
    Write-Host "$Message" -ForegroundColor Red
    exit 1
}

# Get the script directory
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$RepoRoot = $ScriptDir

Write-Info "Starting build and deployment process..."
Write-Info "Repository root: $RepoRoot"

# Step 1: Build Docker image
Write-Info "Step 1: Building Docker image (image tag: hello-world:$ImageTag)"
try {
    Push-Location $RepoRoot
    docker build -t "hello-world:$ImageTag" .
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed"
    }
    Write-Success "Docker image built successfully"
}
catch {
    Write-Error "Failed to build Docker image: $_"
}
finally {
    Pop-Location
}

# Step 2: Build Helm dependencies
Write-Info "Step 2: Building Helm dependencies"
try {
    Push-Location "$RepoRoot\helm\hello-world"
    helm dependency build
    if ($LASTEXITCODE -ne 0) {
        throw "Helm dependency build failed"
    }
    Write-Success "Helm dependencies built successfully"
}
catch {
    Write-Error "Failed to build Helm dependencies: $_"
}

# Step 3: Lint Helm chart
Write-Info "Step 3: Linting Helm chart"
try {
    helm lint .
    if ($LASTEXITCODE -ne 0) {
        throw "Helm lint failed"
    }
    Write-Success "Helm chart linting passed"
}
catch {
    Write-Error "Helm linting failed: $_"
}

# Step 4: Check if chart is already installed
Write-Info "Step 4: Checking for existing Helm release"
$ReleaseName = "hello-world"
$ExistingRelease = helm list -n $Namespace -o json | ConvertFrom-Json | Where-Object { $_.name -eq $ReleaseName }

if ($ExistingRelease) {
    Write-Info "Release '$ReleaseName' already exists. Upgrading..."
    helm upgrade $ReleaseName . `
        --namespace $Namespace `
        --set image.tag=$ImageTag `
        --set image.pullPolicy=IfNotPresent
}
else {
    Write-Info "Step 4: Installing Helm chart"
    helm install $ReleaseName . `
        --namespace $Namespace `
        --create-namespace `
        --set image.tag=$ImageTag `
        --set image.pullPolicy=IfNotPresent
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Helm install/upgrade failed"
}
Write-Success "Helm chart installed/upgraded successfully"

# Step 5: Wait for deployment to be ready
Write-Info "Step 5: Waiting for deployment to be ready..."
kubectl rollout status deployment/$ReleaseName-hello-world -n $Namespace --timeout=2m
if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed to reach ready state"
}
Write-Success "Deployment is ready"

# Step 6: Show deployment status
Write-Info "Step 6: Deployment status"
Write-Host ""
kubectl get pods -n $Namespace -l app.kubernetes.io/name=hello-world
Write-Host ""
kubectl get svc -n $Namespace -l app.kubernetes.io/name=hello-world
Write-Host ""

# Step 7: Port forward
Write-Info "Step 7: Setting up port-forward"
Write-Info "Forwarding localhost:$Port -> service:80"

# Kill any existing port-forward on this port
$ExistingProcess = Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match $Port }
if ($ExistingProcess) {
    Write-Info "Stopping existing port-forward process..."
    Stop-Process -Id $ExistingProcess.Id -Force
    Start-Sleep -Seconds 1
}

# Start port-forward in background
$PortForwardJob = Start-Job -ScriptBlock {
    param($Namespace, $Port, $ReleaseName)
    kubectl port-forward "svc/$ReleaseName-hello-world" "$Port`:80" -n $Namespace
} -ArgumentList $Namespace, $Port, $ReleaseName

Start-Sleep -Seconds 2

# Check if port-forward is running
if ((Get-Job -Id $PortForwardJob.Id).State -eq "Running") {
    Write-Success "Port-forward started successfully (Job ID: $($PortForwardJob.Id))"
}
else {
    Write-Error "Port-forward failed to start"
}

# Step 8: Display access information
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Success "Application is ready!"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Access the application:" -ForegroundColor Yellow
Write-Host "   Main app:   http://localhost:$Port/"
Write-Host "   Health check: http://localhost:$Port/healthz"
Write-Host ""
Write-Host "   Useful commands:" -ForegroundColor Yellow
Write-Host "   View logs:    kubectl logs -f deployment/$ReleaseName-hello-world -n $Namespace"
Write-Host "   Get events:   kubectl get events -n $Namespace"
Write-Host "   Describe pod: kubectl describe pod -l app.kubernetes.io/name=hello-world -n $Namespace"
Write-Host ""
Write-Host "   Cleanup when done:" -ForegroundColor Yellow
Write-Host "   Stop port-forward: Stop-Job -Id $($PortForwardJob.Id)"
Write-Host "   Uninstall chart:   helm uninstall $ReleaseName -n $Namespace"
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Pop-Location