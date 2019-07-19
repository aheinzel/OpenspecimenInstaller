# OpenspecimenInstaller
This is a simple installer (bash script) for openspecimen v6.1RC5 on a fresh Ubuntu 16804 installation. The installer takes care of setting up mySQL and tomcat for openspecimen, builds openspecimen from source and deploys it to the local tomcat instance.

## Configuration
Check the shell variables at the beginning of the installer.

## CAVEATS
* use only on a fresh Ubuntu installation
* openjdk-8 is used
* mySQL and tomcat are automatically installed on the local machine
* mySQL is reconfigure to force the use of lower case table names (this could potentially brake existing application)
* tomcat is reconfigured to use 2GB heap space
* mySQL connector is deployed on tomcat as common library
* version of openspecimens dependency on grunt-contrib-imagemin is incremented to >= 1.0.0
* the installer attempts to automatically download the mySQL connector from mysql.com. In case the zip archive is no longer available the MYSQL_CONNECTOR_* shell variables must be adapted. 
