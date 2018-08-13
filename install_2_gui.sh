#!/usr/bin/env bash

# Gnome Desktop
yum groupinstall "GNOME Desktop" -y
systemctl set-default graphical.target
systemctl isolate graphical.target

# vlc
yum install -y vlc

# Google Chrome
# https://www.tecmint.com/install-google-chrome-on-redhat-centos-fedora-linux/

cat <<EOT > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=google-chrome
baseurl=http://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl-ssl.google.com/linux/linux_signing_key.pub
EOT

yum install -y google-chrome-stable


# GStreamer and codecs
yum install -y http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-5.el7.nux.noarch.rpm
yum install -y gstreamer{,1}-plugins-ugly gstreamer-plugins-bad-nonfree libde265 x265 libdvdcss


echo "NOTE: gui main user should be called 'archive'"

echo "Shutting down in 5 seconds"
shutdown -r 5
