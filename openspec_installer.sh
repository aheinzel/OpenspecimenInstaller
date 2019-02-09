#!/bin/bash
set -e

#############################################################
# INSTALLER FOR OPENSPECIMEN V5.2.x                         #
#                                                           #
# Builds Openspecimen from source and deploys it on tomcat  #
# CAVE: this script automatically installs and RECONFIGURES #
#    tomcat and mySQL                                       #  
#############################################################

### TOMCAT INFO ###
TOMCAT_SERVICE_NAME="tomcat8"
TOMCAT_HOME="/var/lib/tomcat8"
TOMCAT_SHARED_LIB="/usr/share/tomcat8/lib"
TOMCAT_USER="tomcat8"
TOMCAT_GROUP="tomcat8"

### MYSQL INFO ###
MYSQLD_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"

### DATABASE INFO ###
DB_USER="openspecimen"
DB_PASS="openspecimen"
DB_NAME="openspecimen"

### OPENSPECIMEN VERSION INFO (used for checkout) ###
OPENSPECIMEN_GIT_BRANCH="v5.2.x"

### OPENSPECIMEN SYSTEM INFO ###
OPENSPECIMEN_APP_NAME="openspecimen"
OPENSPECIMEN_HOME="/var/lib/openspecimen"
OPENSPECIMEN_DATA="${OPENSPECIMEN_HOME}/data"
OPENSPECIMEN_PLUGINS="${OPENSPECIMEN_HOME}/plugins"

### MYSQL CONNECTOR/J DOWNLOAD ###
MYSQL_CONNECTOR_URL="https://cdn.mysql.com//Downloads/Connector-J/mysql-connector-java-8.0.15.zip"
MYSQL_CONNECTOR_ZIP="mysql-connector-java-8.0.15.zip"
MYSQL_CONNECTOR_JAR="mysql-connector-java-8.0.15/mysql-connector-java-8.0.15.jar"

apt update
apt install -y unzip

## download mySQL Connector/J
cd /tmp
wget "${MYSQL_CONNECTOR_URL}"
unzip "${MYSQL_CONNECTOR_ZIP}"
if [ ! -e "${MYSQL_CONNECTOR_JAR}" ]
then
   echo "MYSQL connector jar not present at ${MYSQL_CONNECTOR_JAR}" >&2
   exit 1
fi

## set config for unattended install of mysql-server and java8
debconf-set-selections <<< 'mysql-server mysql-server/root_password password your_password'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password your_password'
debconf-set-selections <<< 'debconf shared/accepted-oracle-license-v1-1 select true'
debconf-set-selections <<< 'debconf shared/accepted-oracle-license-v1-1 seen true'

## install java 8
apt install -y \
   software-properties-common

add-apt-repository -y ppa:webupd8team/java
apt update
apt-get install -y \
   oracle-java8-installer
   
## install required packages
apt install -y \
   tomcat8 \
   nodejs-legacy \
   npm \
   gradle \
   mysql-server \
   git \
   nano \
   gawk

npm install -g bower grunt-cli

## configure mySQL
systemctl stop mysql
## enforce the use of of lower case table names
if grep 'lower_case_table_names=.*' "${MYSQLD_CONF}"
then
   sed -i 's/lower_case_table_names=.*/lower_case_table_names=1/' "${MYSQLD_CONF}"
else
   sed -i '/\[mysqld\]/a lower_case_table_names=1' "${MYSQLD_CONF}"
fi
systemctl start mysql

## create openspecimen database and user
mysql -uroot << EOF
create database ${DB_NAME};
create user '${DB_USER}'@'localhost' identified by '${DB_PASS}';
grant all on ${DB_NAME}.* to '${DB_USER}'@'localhost';
EOF

## build openspecimen and deploy to tomcat
systemctl stop "${TOMCAT_SERVICE_NAME}"
mkdir "${OPENSPECIMEN_HOME}"
mkdir "${OPENSPECIMEN_DATA}"
mkdir "${OPENSPECIMEN_PLUGINS}"
chown -R ${TOMCAT_USER}:${TOMCAT_GROUP} "${OPENSPECIMEN_HOME}"

## add mySQL connector/J as shared library to tomcat
cp "/tmp/${MYSQL_CONNECTOR_JAR}" "${TOMCAT_SHARED_LIB}"

## create openspecimen configuration file
cat << EOF > "${TOMCAT_HOME}/conf/openspecimen.properties"
app.name=${OPENSPECIMEN_APP_NAME}
tomcat.dir=${TOMCAT_HOME}
app.data_dir=${OPENSPECIMEN_DATA}
plugin.dir=${OPENSPECIMEN_PLUGINS}
datasource.jndi=jdbc/openspecimen
datasource.type=fresh
database.type=mysql
EOF

chown -R ${TOMCAT_USER}:${TOMCAT_GROUP} "${TOMCAT_HOME}/conf/openspecimen.properties"

## add JNDI resource for the openspecimen database
gawk -i inplace '{if($0 ~ /<\/Context>/){print resource} print $0}' resource="$(cat <<-EOF
<Resource name="jdbc/openspecimen" auth="Container" type="javax.sql.DataSource"
      maxActive="100" maxIdle="30" maxWait="10000"
      username="${DB_USER}" password="${DB_PASS}" driverClassName="com.mysql.jdbc.Driver"
      url="jdbc:mysql://127.0.0.1:3306/${DB_NAME}" />
EOF
)" "${TOMCAT_HOME}/conf/context.xml"


## build openspecimen from source (steps are performed under user installuser)
cd /tmp
useradd -m installuser
su installuser << EOF
git clone https://github.com/krishagni/openspecimen.git
cd openspecimen/
git checkout "${OPENSPECIMEN_GIT_BRANCH}"
sed -i "s@app_home=.*@app_home=${TOMCAT_HOME}@" build.properties
cd www
npm install
bower install
cd ..
gradle build
EOF

cd openspecimen
gradle deploy
chown ${TOMCAT_USER}:${TOMCAT_GROUP} "${TOMCAT_HOME}/webapps/openspecimen.war"
userdel -r installuser

## reconfigure tomcat to use 2GB heap space
sed -i -r 's/(JAVA_OPTS=.*)-Xmx[^ ]+(.*)/\1-Xmx2048m\2/' /etc/default/tomcat8

systemctl start "${TOMCAT_SERVICE_NAME}"