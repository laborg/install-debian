#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi

### fail on any error
set -e

### update apt
apt-get update

### install general packages
apt-get -y install sudo wget lsb-release gnupg

### check if we are on debian stretch
if [ "$(lsb_release -d | grep -vEi 'debian.*stretch')" ]; then
  exit 1
fi

### install additional apt source lists and update again
bash -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
wget -q  --quiet https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | apt-key add -
apt-get update

### install OpenJDK 8
apt-get -y install openjdk-8-jdk

### install tomcat8
apt-get -y install libservlet3.1-java tomcat8

### install apache2
apt-get -y install apache2 libapache2-mod-jk libapache2-mod-fcgid

### install postgresql
apt-get -y install postgresql-9.5
