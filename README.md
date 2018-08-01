BB Archive box
===

Installation instructions for a fresh BB Archive in a box (suitcase).


Architecture overview:
==

Archive in a box is made out of two parts (over simplified): brain and files.
Where brain stands for all apps, services, data stores, assets which are not the actual content of the archive.
These are the content files themselves (video, audio, etc...)


Installation steps:
==

Once the box is setup with Centos 7.

as root

1. clone or download this repo
2. edit `install.env` with proper values
3. run `install_1_archive.sh`
4. run `install_2_gui.sh`
5. log in the gui and run `install_3_user_apps.sh`


setup ssh access to the box ```ssh-copy-id root@<suitcase-ip>```
and login