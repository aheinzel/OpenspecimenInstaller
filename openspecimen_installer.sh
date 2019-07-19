#!/bin/bash
set -e

#############################################################
# INSTALLER FOR OPENSPECIMEN V6.1.RC5                       #
#                                                           #
# Builds Openspecimen from source and deploys it on tomcat  #
# CAVE: this script automatically installs and RECONFIGURES #
#    tomcat and mySQL                                       #  
#############################################################

### TOMCAT INFO ###
TOMCAT_SERVICE_NAME="tomcat9"
TOMCAT_HOME="/var/lib/tomcat9"
TOMCAT_SHARED_LIB="/usr/share/tomcat9/lib"
TOMCAT_SYSTEMD_UNIT_FILE="/etc/systemd/system/multi-user.target.wants/tomcat9.service"
TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"

### MYSQL INFO ###
MYSQLD_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"

### DATABASE INFO ###
DB_USER="openspecimen"
DB_PASS="openspecimen"
DB_NAME="openspecimen"

### OPENSPECIMEN VERSION INFO (used for checkout) ###
OPENSPECIMEN_GIT_BRANCH="v6.1.RC5"

### OPENSPECIMEN SYSTEM INFO ###
OPENSPECIMEN_APP_NAME="openspecimen"
OPENSPECIMEN_HOME="/var/lib/openspecimen"
OPENSPECIMEN_DATA="${OPENSPECIMEN_HOME}/data"
OPENSPECIMEN_PLUGINS="${OPENSPECIMEN_HOME}/plugins"
OPENSPECIMEN_PACKAGE_JSON_PATCH=$(cat <<EOF
--- package.json        2019-07-17 15:14:00.419021754 +0000
+++ package.json.new    2019-07-18 04:27:36.961700752 +0000
@@ -34,7 +34,7 @@
     "grunt-contrib-copy": "^0.7.0",
     "grunt-contrib-cssmin": "^0.10.0",
     "grunt-contrib-htmlmin": "^0.3.0",
-    "grunt-contrib-imagemin": "0.9.1",
+    "grunt-contrib-imagemin": "^1.0.0",
     "grunt-contrib-uglify": "^0.6.0",
     "grunt-contrib-watch": "^0.6.1",
     "grunt-filerev": "^2.1.1",
EOF
)

### MYSQL CONNECTOR/J DOWNLOAD ###
MYSQL_CONNECTOR_URL="https://cdn.mysql.com//Downloads/Connector-J/mysql-connector-java-8.0.15.zip"
MYSQL_CONNECTOR_ZIP="mysql-connector-java-8.0.15.zip"
MYSQL_CONNECTOR_JAR="mysql-connector-java-8.0.15/mysql-connector-java-8.0.15.jar"

apt update -q
apt install -y -q unzip

## download mySQL Connector/J
cd /tmp
wget "${MYSQL_CONNECTOR_URL}"
unzip "${MYSQL_CONNECTOR_ZIP}"
if [ ! -e "${MYSQL_CONNECTOR_JAR}" ]
then
   echo "MYSQL connector jar not present at ${MYSQL_CONNECTOR_JAR}" >&2
   exit 1
fi

## install required packages
DEBIAN_PRIORITY=critical apt install -y -q \
   mysql-server


apt install -y -q \
   openjdk-8-jre-headless \
   openjdk-8-jdk-headless \
   tomcat9 \
   nodejs \
   npm \
   gradle \
   git \
   nano \
   gawk \
   libpng-dev

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

##use UTF8
if grep 'character-set-server=.*' "${MYSQLD_CONF}"
then
   sed -i 's/character-set-server=.*/character-set-server=utf8/' "${MYSQLD_CONF}"
else
   sed -i '/\[mysqld\]/a character-set-server=utf8' "${MYSQLD_CONF}"
fi

#Note: could also set encoding for client

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
export TOMCAT_HOME OPENSPECIMEN_PACKAGE_JSON_PATCH OPENSPECIMEN_GIT_BRANCH
cd /tmp
useradd -m installuser
su installuser << 'EOF'
git clone https://github.com/krishagni/openspecimen.git
cd openspecimen/
git checkout "${OPENSPECIMEN_GIT_BRANCH}"
sed -i "s@app_home=.*@app_home=${TOMCAT_HOME}@" build.properties
cd www
echo "${OPENSPECIMEN_PACKAGE_JSON_PATCH}" | patch
npm install
bower install
cd ..
gradle build
gradle --stop
EOF

cd openspecimen
gradle deploy
chown ${TOMCAT_USER}:${TOMCAT_GROUP} "${TOMCAT_HOME}/webapps/openspecimen.war"
userdel -r installuser

## reconfigure tomcat to use 2GB heap space
## ATT: assume JAVA_OPTS is present
sed -i -r 's/^(JAVA_OPTS=.*)"/\1 -Xmx2048m"/' "/etc/default/${TOMCAT_SERVICE_NAME}"

## allow tomcat to write to openspecimen home directory
gawk -i inplace '{if($0 ~ /\[Service\]/){print $0; print perm;}else{print $0}}' \
   perm="ReadWritePaths=${OPENSPECIMEN_HOME}" "${TOMCAT_SYSTEMD_UNIT_FILE}"

systemctl start "${TOMCAT_SERVICE_NAME}"
