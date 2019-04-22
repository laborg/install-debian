#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

### install all dependencies
./prepare_debian_stretch.sh

### create 'ctsms' user
useradd ctsms -p '*' --groups sudo

### prepare /ctsms directory with default-config and master-data
mkdir /ctsms
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/dbtool.sh -O /ctsms/dbtool.sh
chown ctsms:ctsms /ctsms/dbtool.sh
chmod 755 /ctsms/dbtool.sh
wget --no-check-certificate --content-disposition https://github.com/phoenixctms/config-default/archive/master.tar.gz -O /ctsms/config.tar.gz
tar -zxvf /ctsms/config.tar.gz -C /ctsms --strip-components 1
rm /ctsms/config.tar.gz -f
wget https://api.github.com/repos/phoenixctms/master-data/tarball/master -O /ctsms/master-data.tar.gz
mkdir /ctsms/master_data
tar -zxvf /ctsms/master-data.tar.gz -C /ctsms/master_data --strip-components 1
rm /ctsms/master-data.tar.gz -f
chown ctsms:ctsms /ctsms -R

### setup tomcat8
systemctl stop tomcat8
usermod --append --groups tomcat8,adm ctsms
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/workers.properties -O /etc/tomcat8/workers.properties
chown root:tomcat8 /etc/tomcat8/workers.properties
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/server.xml -O /etc/tomcat8/server.xml
chown root:tomcat8 /etc/tomcat8/server.xml
chmod 640 /etc/tomcat8/workers.properties
chmod 770 /var/log/tomcat8
chmod g+w /var/log/tomcat8/*
chmod 775 /var/lib/tomcat8/webapps
sed -r -i 's/TOMCAT8_USER.+/TOMCAT8_USER=ctsms/' /etc/default/tomcat8
sed -r -i 's/TOMCAT8_GROUP.+/TOMCAT8_GROUP=ctsms/' /etc/default/tomcat8
sed -r -i 's/^JAVA_OPTS.+/JAVA_OPTS="-server -Djava.awt.headless=true -Xms2048m -Xmx4096m -Xss256k -XX:+UseParallelGC -XX:MaxGCPauseMillis=1500 -XX:GCTimeRatio=9 -XX:+CMSClassUnloadingEnabled -XX:ReservedCodeCacheSize=256m"/' /etc/default/tomcat8
echo 'CTSMS_PROPERTIES=/ctsms/properties' >>/etc/default/tomcat8
systemctl start tomcat8

### build phoenix
apt-get -y install git maven
mkdir /ctsms/build
cd /ctsms/build
git clone https://github.com/phoenixctms/ctsms
sed -r -i 's/<java\.home>.+<\/java\.home>/<java.home>\/usr\/lib\/jvm\/java-8-openjdk-amd64<\/java.home>/' /ctsms/build/ctsms/pom.xml
sed -r -i 's/<stagingDirectory>.+<\/stagingDirectory>/<stagingDirectory>\/ctsms\/build\/ctsms\/target\/site<\/stagingDirectory>/' /ctsms/build/ctsms/pom.xml
cd /ctsms/build/ctsms
mvn -Peclipse -Dmaven.test.skip=true
mvn -f core/pom.xml org.andromda.maven.plugins:andromdapp-maven-plugin:schema -Dtasks=create
mvn -f core/pom.xml org.andromda.maven.plugins:andromdapp-maven-plugin:schema -Dtasks=drop

### setup postgres 9.5
sudo -u postgres psql postgres -c "CREATE USER ctsms WITH PASSWORD 'ctsms';"
sudo -u postgres psql postgres -c "CREATE DATABASE ctsms;"
sudo -u postgres psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE ctsms to ctsms;"
sudo -u ctsms psql -U ctsms ctsms < /ctsms/build/ctsms/core/db/schema-create.sql

### enable ssh and database remote access
#apt-get -y install ssh
#sed -r -i "s|#*listen_addresses.*|listen_addresses = '*'|" /etc/postgresql/9.5/main/postgresql.conf
#echo -e "host\tall\tall\t0.0.0.0/0\tmd5\nhost\tall\tall\t::/0\tmd5" >> /etc/postgresql/9.5/main/pg_hba.conf
#systemctl restart postgresql

### deploy ctsms-web.war
chmod 755 /ctsms/build/ctsms/web/target/ctsms-1.6.2.war
rm /var/lib/tomcat8/webapps/ROOT/ -rf
cp /ctsms/build/ctsms/web/target/ctsms-1.6.2.war /var/lib/tomcat8/webapps/ROOT.war

###setup apache2
usermod --append --groups tomcat8,ctsms www-data
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/00_ctsms_http.conf -O /etc/apache2/sites-available/00_ctsms_http.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/00_ctsms_https.conf -O /etc/apache2/sites-available/00_ctsms_https.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/01_signup_http.conf -O /etc/apache2/sites-available/01_signup_http.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/01_signup_https.conf -O /etc/apache2/sites-available/01_signup_https.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/ports.conf -O /etc/apache2/ports.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/blocklist.conf -O /etc/apache2/blocklist.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/jk.conf -O /etc/apache2/mods-available/jk.conf
a2dissite 000-default.conf
a2ensite 00_ctsms_https.conf
a2ensite 00_ctsms_http.conf
a2enmod ssl
a2enmod rewrite
a2enmod deflate

###deploy server certificate
mkdir /etc/apache2/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/apache2/ssl/apache.key -subj "/C=AT/ST=Austria/L=Graz/O=phoenix/CN=$HOSTNAME" -out /etc/apache2/ssl/apache.crt
chmod 600 /etc/apache2/ssl/*
systemctl reload apache2

###install bulk-processor
apt-get -y install \
libtest-utf8-perl \
libmoose-perl \
libmoosex-hasdefaults-perl \
libarchive-zip-perl \
libconfig-any-perl \
libdata-dump-perl \
libdata-dumper-concise-perl \
libdata-uuid-perl \
libdata-validate-ip-perl \
libdate-calc-perl \
libdate-manip-perl \
libdatetime-format-iso8601-perl \
libdatetime-format-strptime-perl \
libdatetime-perl \
libdatetime-timezone-perl \
libdbd-csv-perl \
libdbd-mysql-perl \
libdbd-sqlite3-perl \
libdigest-md5-perl \
libemail-mime-attachment-stripper-perl \
libemail-mime-perl \
libgearman-client-perl \
libhtml-parser-perl \
libintl-perl \
libio-compress-perl \
libio-socket-ssl-perl \
libjson-xs-perl \
liblog-log4perl-perl \
libmail-imapclient-perl \
libmarpa-r2-perl \
libmime-base64-perl \
libmime-lite-perl \
libmime-tools-perl \
libnet-address-ip-local-perl \
libnet-smtp-ssl-perl \
libole-storage-lite-perl \
libphp-serialization-perl \
libexcel-writer-xlsx-perl \
libspreadsheet-parseexcel-perl \
libstring-mkpasswd-perl \
libtext-csv-xs-perl \
libtie-ixhash-perl \
libtime-warp-perl \
liburi-find-perl \
libuuid-perl \
libwww-perl \
libxml-dumper-perl \
libxml-libxml-perl \
libyaml-libyaml-perl \
libyaml-tiny-perl \
libtemplate-perl \
libdancer-perl \
libdbd-pg-perl \
libjson-perl \
libplack-perl \
memcached \
libcache-memcached-perl \
libdancer-session-memcached-perl \
libgraphviz-perl \
gnuplot \
imagemagick \
ghostscript \
build-essential \
cpanminus \
libsys-cpuaffinity-perl

### install modules not available as debs
cpanm Dancer::Plugin::I18N
cpanm Spreadsheet::Reader::Format
cpanm Spreadsheet::Reader::ExcelXML
#wget --no-check-certificate --content-disposition https://github.com/phoenixctms/bulk-processor/archive/master.tar.gz -O /usr/lib/x86_64-linux-gnu/perl5/5.24/bulk-processor.tar.gz
#tar -zxvf /usr/lib/x86_64-linux-gnu/perl5/5.24/bulk-processor.tar.gz -C /usr/lib/x86_64-linux-gnu/perl5/5.24 --strip-components 1
#chmod 755 /usr/lib/x86_64-linux-gnu/perl5/5.24/CTSMS -R
#chmod 755 /usr/lib/x86_64-linux-gnu/perl5/5.24/Excel -R
#rm /usr/lib/x86_64-linux-gnu/perl5/5.24//bulk-processor.tar.gz -f
wget --no-check-certificate --content-disposition https://github.com/phoenixctms/bulk-processor/archive/master.tar.gz -O /ctsms/bulk-processor.tar.gz
tar -zxvf /ctsms/bulk-processor.tar.gz -C /ctsms/bulk_processor --strip-components 1
mkdir /ctsms/bulk_processor/output
chown ctsms:ctsms /ctsms/bulk_processor -R
chmod 755 /ctsms/bulk_processor -R
chmod 777 /ctsms/bulk_processor/output -R
rm /ctsms/bulk-processor.tar.gz -f
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/ecrfdataexport.sh -O /ctsms/ecrfdataexport.sh
chown ctsms:ctsms /ctsms/ecrfdataexport.sh
chmod 755 /ctsms/ecrfdataexport.sh

###initialize phoenix
sudo -u ctsms /ctsms/dbtool.sh -i -f
sudo -u ctsms /ctsms/dbtool.sh -icp /ctsms/master_data/criterion_property_definitions.csv
sudo -u ctsms /ctsms/dbtool.sh -ipd /ctsms/master_data/permission_definitions.csv
sudo -u ctsms /ctsms/dbtool.sh -imi /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -ims /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imc /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imt /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imp /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -immm /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imifi /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imsi /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -impi /ctsms/master_data/mime.types -e ISO-8859-1

sudo -u ctsms /ctsms/dbtool.sh -it /ctsms/master_data/titles.csv -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -ib /ctsms/master_data/kiverzeichnis_gesamt_de_1347893202433.csv -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -ic /ctsms/master_data/countries.txt -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -iz /ctsms/master_data/streetnames.csv -e utf-8
sudo -u ctsms /ctsms/dbtool.sh -is /ctsms/master_data/streetnames.csv -e utf-8

sudo -u ctsms /ctsms/dbtool.sh -iis /ctsms/master_data/icd10gm2012syst_claml_20110923.xml -sl de
sudo -u ctsms /ctsms/dbtool.sh -iai /ctsms/master_data/icd10gm2012_alphaid_edv_ascii_20110930.txt -e ISO-8859-1 -isr icd10gm2012syst_claml_20110923
sudo -u ctsms /ctsms/dbtool.sh -ios /ctsms/master_data/ops2012syst_claml_20111103.xml -sl de
sudo -u ctsms /ctsms/dbtool.sh -ioc /ctsms/master_data/ops2011alpha_edv_ascii_20111031.txt -osr ops2012syst_claml_20111103
sudo -u ctsms /ctsms/dbtool.sh -ia /ctsms/master_data/asp_register_20181005.xls

DEPARTMENT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
USER_PASSWORD=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 3 | head -n 1)
sudo -u ctsms /ctsms/dbtool.sh -cd -dlk my_department -dp "$DEPARTMENT_PASSWORD"
sudo -u ctsms /ctsms/dbtool.sh -cu -dlk my_department -dp "$DEPARTMENT_PASSWORD" -u "phoenix" -p "$USER_PASSWORD" -pp "INVENTORY_MASTER_ALL_DEPARTMENTS,STAFF_MASTER_ALL_DEPARTMENTS,COURSE_MASTER_ALL_DEPARTMENTS,TRIAL_MASTER_ALL_DEPARTMENTS,PROBAND_MASTER_ALL_DEPARTMENTS,USER_ALL_DEPARTMENTS,INPUT_FIELD_MASTER,MASS_MAIL_MASTER_ALL_DEPARTMENTS,INVENTORY_MASTER_SEARCH,STAFF_MASTER_SEARCH,COURSE_MASTER_SEARCH,TRIAL_MASTER_SEARCH,PROBAND_MASTER_SEARCH,USER_MASTER_SEARCH,INPUT_FIELD_MASTER_SEARCH,MASS_MAIL_MASTER_SEARCH"

sudo -u ctsms /ctsms/dbtool.sh -cu -dlk my_department -dp "$DEPARTMENT_PASSWORD" -u "my_department_signup_de" -p "my_department_signup_de" -ul de -pp "INVENTORY_VIEW_USER_DEPARTMENT,STAFF_DETAIL_IDENTITY,COURSE_VIEW_USER_DEPARTMENT,TRIAL_SIGNUP,PROBAND_SIGNUP,USER_ACTIVE_USER,INPUT_FIELD_VIEW,MASS_MAIL_SIGNUP,INVENTORY_NO_SEARCH,STAFF_NO_SEARCH,COURSE_NO_SEARCH,TRIAL_NO_SEARCH,PROBAND_NO_SEARCH,USER_NO_SEARCH,INPUT_FIELD_NO_SEARCH,MASS_MAIL_NO_SEARCH"
sudo -u ctsms /ctsms/dbtool.sh -cu -dlk my_department -dp "$DEPARTMENT_PASSWORD" -u "my_department_signup_en" -p "my_department_signup_en" -ul en -pp "INVENTORY_VIEW_USER_DEPARTMENT,STAFF_DETAIL_IDENTITY,COURSE_VIEW_USER_DEPARTMENT,TRIAL_SIGNUP,PROBAND_SIGNUP,USER_ACTIVE_USER,INPUT_FIELD_VIEW,MASS_MAIL_SIGNUP,INVENTORY_NO_SEARCH,STAFF_NO_SEARCH,COURSE_NO_SEARCH,TRIAL_NO_SEARCH,PROBAND_NO_SEARCH,USER_NO_SEARCH,INPUT_FIELD_NO_SEARCH,MASS_MAIL_NO_SEARCH"

CRON_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
sudo -u ctsms /ctsms/dbtool.sh -cu -dlk my_department -dp "$DEPARTMENT_PASSWORD" -u "my_department_cron" -p "$CRON_PASSWORD" -pp "INVENTORY_MASTER_ALL_DEPARTMENTS,STAFF_MASTER_ALL_DEPARTMENTS,COURSE_MASTER_ALL_DEPARTMENTS,TRIAL_MASTER_ALL_DEPARTMENTS,PROBAND_MASTER_ALL_DEPARTMENTS,USER_ALL_DEPARTMENTS,INPUT_FIELD_MASTER,MASS_MAIL_MASTER_ALL_DEPARTMENTS,INVENTORY_MASTER_SEARCH,STAFF_MASTER_SEARCH,COURSE_MASTER_SEARCH,TRIAL_MASTER_SEARCH,PROBAND_MASTER_SEARCH,USER_MASTER_SEARCH,INPUT_FIELD_MASTER_SEARCH,MASS_MAIL_MASTER_SEARCH"
sed -r -i "s|ctsmsrestapi_password.*|ctsmsrestapi_password = ${CRON_PASSWORD}|" /ctsms/bulk_processor/CTSMS/BulkProcessor/Projects/ETL/Criteria/config.cfg
sed -r -i "s|ctsmsrestapi_password.*|ctsmsrestapi_password = ${CRON_PASSWORD}|" /ctsms/bulk_processor/CTSMS/BulkProcessor/Projects/ETL/Duplicates/config.cfg
sed -r -i "s|ctsmsrestapi_password.*|ctsmsrestapi_password = ${CRON_PASSWORD}|" /ctsms/bulk_processor/CTSMS/BulkProcessor/Projects/ETL/EcrfExporter/config.cfg
IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
sed -r -i "s|ctsms_base_uri.*|ctsms_base_uri: 'https://${IP}'|" /ctsms/bulk_processor/CTSMS/BulkProcessor/Projects/ETL/EcrfExporter/settings.yml

###create some default queries/reports
cd /ctsms/bulk_processor/CTSMS/BulkProcessor/Projects/ETL/Criteria
perl process.pl --task=create_criteria --force --skip-errors

###render workflow state diagram images from db and include them for tooltips
cd /ctsms/bulk_processor/CTSMS/BulkProcessor/Projects/Render
./render.sh
cd /ctsms/build/ctsms
mvn -f web/pom.xml -Dmaven.test.skip=true
chmod 755 /ctsms/build/ctsms/web/target/ctsms-1.6.2.war
systemctl stop tomcat8
rm /var/lib/tomcat8/webapps/ROOT/ -rf
cp /ctsms/build/ctsms/web/target/ctsms-1.6.2.war /var/lib/tomcat8/webapps/ROOT.war

###ready
systemctl start tomcat8
echo "Phoenix CTMS is starting..."
echo "The department passphrase for 'my_department' when adding users with /ctsms/dbtool.sh is '$DEPARTMENT_PASSWORD'."
echo "Log in at https://$IP with username 'phoenix' password '$USER_PASSWORD'."
