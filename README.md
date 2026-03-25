# ..\helm\lib-common\templates\_deployment.tpl
Fixed indentation issue in lib-common deployment template.
The ports field must be a property of the container object

Chart running on local cluster:

![alt text](images\apprunning.png)

![alt text](images\apphealthz.png)

![alt text](images\pods.png)

![alt text](images\service.png)