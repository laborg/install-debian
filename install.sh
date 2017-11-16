###install some general packages:
#apt-get -y install mc open-vm-tools net-tools

###create 'ctsms' user
useradd ctsms -p '*' --groups sudo
usermod www-data --append --groups ctsms

###install java 6
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/jdk-6u45-linux-x64.bin -O /opt/jdk-6u45-linux-x64.bin
chmod 744 /opt/jdk-6u45-linux-x64.bin
cd /opt
/opt/jdk-6u45-linux-x64.bin
rm /opt/jdk-6u45-linux-x64.bin -f

###install tomcat6
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/apache-tomcat-6.0.48.tar.gz -O /opt/apache-tomcat-6.0.48.tar.gz
tar -zxvf /opt/apache-tomcat-6.0.48.tar.gz -C /opt
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/server.xml -O /opt/apache-tomcat-6.0.48/conf/server.xml
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/workers.properties -O /opt/apache-tomcat-6.0.48/conf/workers.properties
chown ctsms:ctsms /opt/apache-tomcat-6.0.48 -R
rm /opt/apache-tomcat-6.0.48.tar.gz -f
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/tomcat.service -O /lib/systemd/system/tomcat.service
ln -s /lib/systemd/system/tomcat.service /etc/systemd/system/multi-user.target.wants/tomcat.service
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/tomcat.service.conf -O /etc/systemd/tomcat.service.conf
mkdir /run/tomcat
chown ctsms:ctsms /run/tomcat
chmod 755 /run/tomcat
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/tomcat.conf -O /etc/tmpfiles.d/tomcat.conf
systemctl start tomcat

###prepare /ctsms directory with default-config and master-data
mkdir /ctsms
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/dbtool.sh -O /ctsms/dbtool.sh
chmod 755 /ctsms/dbtool.sh
chown ctsms:ctsms /ctsms/dbtool.sh
wget --no-check-certificate --content-disposition https://github.com/phoenixctms/config-default/archive/master.tar.gz -O /ctsms/config-default.tar.gz
tar -zxvf /ctsms/config-default.tar.gz -C /ctsms --strip-components 1
rm /ctsms/config-default.tar.gz -f
wget https://api.github.com/repos/phoenixctms/master-data/tarball/master -O /ctsms/master-data.tar.gz
mkdir /ctsms/master_data
tar -zxvf /ctsms/master-data.tar.gz -C /ctsms/master_data --strip-components 1
rm /ctsms/master-data.tar.gz -f
chown ctsms:ctsms /ctsms -R
chmod 777 /ctsms -R

####build phoenix
apt-get -y install git
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/primefacesorg.der -O /opt/primefacesorg.der
/opt/jdk1.6.0_45/bin/keytool -import -noprompt -storepass changeit -alias primefacesorg -keystore /opt/jdk1.6.0_45/jre/lib/security/cacerts -file /opt/primefacesorg.der
rm /opt/primefacesorg.der -f
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/bcprov-ext-jdk15on-154.jar -O /opt/jdk1.6.0_45/jre/lib/ext/bcprov-ext-jdk15on-154.jar
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/bcprov-jdk15on-154.jar -O /opt/jdk1.6.0_45/jre/lib/ext/bcprov-jdk15on-154.jar
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/java.security -O /opt/jdk1.6.0_45/jre/lib/security/java.security
mkdir /ctsms/build
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/apache-maven-3.2.5-bin.tar.gz -O /ctsms/build/apache-maven-3.2.5-bin.tar.gz
cd /ctsms/build
tar -zxf /ctsms/build/apache-maven-3.2.5-bin.tar.gz
ln -s /ctsms/build/apache-maven-3.2.5/bin/mvn /usr/bin/mvn
rm /ctsms/build/apache-maven-3.2.5-bin.tar.gz -f
export JAVA_HOME=/opt/jdk1.6.0_45
git clone https://github.com/phoenixctms/ctsms
sed -r -i 's/<java\.home>.+<\/java\.home>/<java.home>\/opt\/jdk1.6.0_45<\/java.home>/' /ctsms/build/ctsms/pom.xml
sed -r -i 's/<stagingDirectory>.+<\/stagingDirectory>/<stagingDirectory>\/ctsms\/build\/ctsms\/target\/site<\/stagingDirectory>/' /ctsms/build/ctsms/pom.xml
cd /ctsms/build/ctsms
mvn -Peclipse -Dmaven.test.skip=true
mvn -f core/pom.xml org.andromda.maven.plugins:andromdapp-maven-plugin:schema -Dtasks=create
mvn -f core/pom.xml org.andromda.maven.plugins:andromdapp-maven-plugin:schema -Dtasks=drop

###install postgres 9.5
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/pgdg.list -O /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update 
apt-get -y install postgresql-9.5
sudo -u postgres psql postgres -c "CREATE USER ctsms WITH PASSWORD 'ctsms';"
sudo -u postgres psql postgres -c "CREATE DATABASE ctsms;"
sudo -u postgres psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE ctsms to ctsms;"
sudo -u ctsms psql -U ctsms ctsms < /ctsms/build/ctsms/core/db/schema-create.sql

###deploy ctsms-web.war
chmod 755 /ctsms/build/ctsms/web/target/ctsms-1.6.0.war
rm /opt/apache-tomcat-6.0.48/webapps/ROOT/ -rf
cp /ctsms/build/ctsms/web/target/ctsms-1.6.0.war /opt/apache-tomcat-6.0.48/webapps/ROOT.war

###setup apache2
apt-get -y install libapache2-mod-jk
apt-get -y install libapache2-mod-fcgid
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/00_ctsms_http.conf -O /etc/apache2/sites-available/00_ctsms_http.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/00_ctsms_https.conf -O /etc/apache2/sites-available/00_ctsms_https.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/01_signup_http.conf -O /etc/apache2/sites-available/01_signup_http.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/01_signup_https.conf -O /etc/apache2/sites-available/01_signup_https.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/ports.conf -O /etc/apache2/ports.conf
wget https://raw.githubusercontent.com/phoenixctms/install-debian/master/jk.conf -O /etc/apache2/mods-available/jk.conf
a2dissite 000-default.conf
a2ensite 00_ctsms_https.conf
a2ensite 00_ctsms_http.conf
a2enmod ssl
a2enmod rewrite

###deploy server certificate
mkdir /etc/apache2/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/apache2/ssl/apache.key -subj "/C=AT/ST=Austria/L=Graz/O=phoenix/CN=localhost" -out /etc/apache2/ssl/apache.crt
chmod 600 /etc/apache2/ssl/*
systemctl reload apache2

###install bulk-processor
apt-get -y install libsys-cpuaffinity-perl libarchive-zip-perl libconfig-any-perl libdata-dump-perl libdata-dumper-concise-perl libdata-uuid-perl libdata-validate-ip-perl libdate-calc-perl libdate-manip-perl libdatetime-format-iso8601-perl libdatetime-format-strptime-perl libdatetime-perl libdatetime-timezone-perl libdbd-csv-perl libdbd-mysql-perl libdbd-sqlite3-perl libdigest-md5-perl libemail-mime-attachment-stripper-perl libemail-mime-perl libgearman-client-perl libhtml-parser-perl libintl-perl libio-compress-perl libio-socket-ssl-perl libjson-xs-perl liblog-log4perl-perl libmail-imapclient-perl libmarpa-r2-perl libmime-base64-perl libmime-lite-perl libmime-tools-perl libnet-address-ip-local-perl libnet-smtp-ssl-perl libole-storage-lite-perl libphp-serialization-perl libexcel-writer-xlsx-perl libspreadsheet-parseexcel-perl libstring-mkpasswd-perl libtext-csv-xs-perl libtie-ixhash-perl libtime-warp-perl liburi-find-perl libuuid-perl libwww-perl libxml-dumper-perl libxml-libxml-perl libyaml-libyaml-perl libyaml-tiny-perl libtemplate-perl libdancer-perl libdbd-pg-perl libjson-perl libplack-perl memcached libcache-memcached-perl libdancer-session-memcached-perl libgraphviz-perl gnuplot imagemagick ghostscript build-essential cpanminus
cpanm Dancer::Plugin::I18N
cpanm Spreadsheet::Reader::Format
cpanm Spreadsheet::Reader::ExcelXML
wget --no-check-certificate --content-disposition https://github.com/phoenixctms/bulk-processor/archive/master.tar.gz -O /usr/lib/x86_64-linux-gnu/perl5/5.24/bulk-processor.tar.gz
tar -zxvf /usr/lib/x86_64-linux-gnu/perl5/5.24/bulk-processor.tar.gz -C /usr/lib/x86_64-linux-gnu/perl5/5.24 --strip-components 1
chmod 755 /usr/lib/x86_64-linux-gnu/perl5/5.24/CTSMS -R
chmod 755 /usr/lib/x86_64-linux-gnu/perl5/5.24/Excel -R
rm /usr/lib/x86_64-linux-gnu/perl5/5.24//bulk-processor.tar.gz -f

###initialize phoenix
sudo -u ctsms /ctsms/dbtool.sh -i -f
sudo -u ctsms /ctsms/dbtool.sh -icp /ctsms/master_data/criterion_property_definitions.csv
sudo -u ctsms /ctsms/dbtool.sh -ipd /ctsms/master_data/permission_definitions.csv
sudo -u ctsms /ctsms/dbtool.sh -imi /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -ims /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imc /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imt /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imp /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imifi /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -imsi /ctsms/master_data/mime.types -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -impi /ctsms/master_data/mime.types -e ISO-8859-1

sudo -u ctsms /ctsms/dbtool.sh -it /ctsms/master_data/titles.csv -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -ib /ctsms/master_data/kiverzeichnis_gesamt_de_1347893202433.csv -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -ic /ctsms/master_data/countries.txt -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -iz /ctsms/master_data/streetnames.csv -e ISO-8859-1
sudo -u ctsms /ctsms/dbtool.sh -is /ctsms/master_data/streetnames.csv -e ISO-8859-1

sudo -u ctsms /ctsms/dbtool.sh -iis /ctsms/master_data/icd10gm2012syst_claml_20110923.xml -sl de
sudo -u ctsms /ctsms/dbtool.sh -iai /ctsms/master_data/icd10gm2012_alphaid_edv_ascii_20110930.txt -e ISO-8859-1 -isr icd10gm2012syst_claml_20110923
sudo -u ctsms /ctsms/dbtool.sh -ios /ctsms/master_data/ops2012syst_claml_20111103.xml -sl de
sudo -u ctsms /ctsms/dbtool.sh -ioc /ctsms/master_data/ops2011alpha_edv_ascii_20111031.txt -osr ops2012syst_claml_20111103

sudo -u ctsms /ctsms/dbtool.sh -cd -dlk my_department -dp "secret MyDepartment passphrase"
sudo -u ctsms /ctsms/dbtool.sh -cu -dlk my_department -dp "secret MyDepartment passphrase" -u "phoenix" -p "phoenix" -pp "INVENTORY_VIEW_USER_DEPARTMENT,STAFF_DETAIL_IDENTITY,COURSE_VIEW_USER_DEPARTMENT,TRIAL_VIEW_USER_DEPARTMENT,PROBAND_VIEW_USER_DEPARTMENT,USER_ALL_DEPARTMENTS,INPUT_FIELD_VIEW,INVENTORY_SAVED_SEARCH,STAFF_SAVED_SEARCH,COURSE_SAVED_SEARCH,TRIAL_SAVED_SEARCH,PROBAND_SAVED_SEARCH,USER_MASTER_SEARCH,INPUT_FIELD_SAVED_SEARCH"

###ready
systemctl restart tomcat
echo "Ready! Log in at https://$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/') with username 'phoenix' and password 'phoenix'"