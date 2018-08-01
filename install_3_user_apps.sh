#!/usr/bin/env bash

# vlc
yum install -y vlc

# LibreOffice
# https://www.libreoffice.org/download/download/
wget https://ftp.gwdg.de/pub/tdf/libreoffice/stable/6.0.3/rpm/x86_64/LibreOffice_6.0.3_Linux_x86-64_rpm.tar.gz
tar -xvf LibreOffice_6.0.3_Linux_x86-64_rpm.tar.gz
cd LibreOffice_6.0.3.2_Linux_x86-64_rpm/RPMS/
yum localinstall *.rpm

