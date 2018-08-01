#!/usr/bin/env bash

# Gnome Desktop
yum groupinstall "GNOME Desktop" -y
systemctl set-default graphical.target
systemctl isolate graphical.target

echo "NOTE: gui main user should be called 'archive'"

echo "Shutting down in 5 seconds"
shutdown -r 5
