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


Disaster Recovery
==

During an unfortunate situation where network is partitioned we want a suitcase instance to serve whatever it has.
To do that a user must set his `/etc/hosts` file to the suitcase ip.

```
127.0.0.1	archive
127.0.0.1	cdn.archive
127.0.0.1	files.archive
```

Once this domains are resolved to the suitcase, the user can simply point his browser to http://archive


### Changing Domains

Changing the domain name of the suitcase instance requires changing comfiguration of various components:
* nginx config files
* service config files
* CI server suitcase jobs

Once these are changed correctly, users have to setup their `/etc/hosts` file accordingly.

**nginx** Each nginx config files under `/etc/nginx/conf.d` must change its `server_name` directive to the new domain.

**TODO:** more details regarding the other two should follow


### Public Access

In a case we want our suitcase be publicly available on the internet (not so safe). Sys Admin has to follow the procedure of changing domains above.

