#!/usr/bin/env bash
set +e
set -x

SCRIPT_BASE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Archive Suitcase install script
# On a fresh CentOS 7 minimal installation


# RPM Fusion and EPEL Repositories
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install -y https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm

# Setup Access over ssh (skip if you already have access)
cat <<EOT > /etc/ssh/sshd_config
PermitRootLogin yes
PermitEmptyPasswords no
PasswordAuthentication yes
EOT

systemctl restart sshd

# To allow access to this suitcase from your own workstation
# Do this on your machine
# ssh-copy-id root@<suitcase-ip>

# Archive Apps and Services

mkdir /sites/
mkdir -p /backup/{mdb,es,github}
chmod a+w /backup/{mdb,es,github}


# Postgresql (9.6)
# https://www.postgresql.org/download/linux/redhat/

yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum install -y postgresql96 postgresql96-server
/usr/pgsql-9.6/bin/postgresql96-setup initdb
systemctl enable postgresql-9.6
sed -i 's/ident/trust/g' /var/lib/pgsql/9.6/data/pg_hba.conf
systemctl start postgresql-9.6
echo ${MDB_PGPASS} > /root/.pgpass
chmod 0600 /root/.pgpass
#cp /root/.pgpass /home/archive
#chown archive:archive /home/archive/.pgpass

# Create ‘archive’ superuser
su postgres -c 'psql -c "CREATE USER archive WITH SUPERUSER;"'
su postgres -c 'psql -c "CREATE USER root WITH SUPERUSER;"'


# ElasticSearch
# https://www.elastic.co/guide/en/elasticsearch/reference/5.6/rpm.html
# https://www.elastic.co/guide/en/elasticsearch/reference/5.5/modules-snapshots.html

yum install -y java-1.8.0-openjdk-devel

rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
cat <<EOT > /etc/yum.repos.d/elasticsearch.repo
[elasticsearch-6.x]
name=Elasticsearch repository for 6.x packages
baseurl=https://artifacts.elastic.co/packages/6.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOT
yum install -y elasticsearch
systemctl enable elasticsearch
systemctl start elasticsearch
cat <<EOT >> /etc/elasticsearch/elasticsearch.yml
bootstrap.memory_lock: true

# Disable system call filters
bootstrap.system_call_filter: false

# snapshot repo
path.repo: ["/backup/es"]
EOT
#echo "exclude=elasticsearch*" >> /etc/yum.conf

systemctl restart elasticsearch
mkdir -p /etc/elasticsearch/hunspell/he_IL
wget -O /etc/elasticsearch/hunspell/he_IL/he_IL.aff https://raw.githubusercontent.com/elastic/hunspell/master/dicts/he_IL/he_IL.aff
wget -O /etc/elasticsearch/hunspell/he_IL/he_IL.dic https://raw.githubusercontent.com/elastic/hunspell/master/dicts/he_IL/he_IL.dic
wget -O /etc/elasticsearch/hunspell/he_IL/settings.yml https://raw.githubusercontent.com/elastic/hunspell/master/dicts/he_IL/settings.yml

systemctl restart elasticsearch
sleep 10s
curl -XPUT 'http://localhost:9200/_snapshot/backup' -H 'Content-Type: application/json' -d '{
    "type": "fs",
    "settings": {
        "location": "/backup/es",
        "compress": true
    }
}'



# Prepare rsync over ssh

# On each relevant production machine we need a ‘suitcase’ unprivileged user to be able to copy files into the suitcase:
# useradd suitcase
# passwd suitcase

yum install -y sshpass
echo -e "\n\n\n" | ssh-keygen -t rsa -b 4096 -C "archive@suitcase.bbdomain.org"
sshpass -p "${SUITCASE_REMOTE_PASS}" ssh-copy-id suitcase@app.archive.bbdomain.org
sshpass -p "${SUITCASE_REMOTE_PASS}" ssh-copy-id suitcase@elastic.archive.bbdomain.org



# Setup and run first sync for MDB and ES
cp ${SCRIPT_BASE}/script/sync.sh /backup
chmod +x /backup/sync.sh
exec /backup/sync.sh



# Nginx
yum install -y nginx policycoreutils-python
systemctl enable nginx
systemctl start nginx
firewall-cmd --zone=public --permanent --add-service=http
firewall-cmd --zone=public --permanent --add-service=https
firewall-cmd --reload
# SELinux and nginx party: https://www.nginx.com/blog/nginx-se-linux-changes-upgrading-rhel-6-6/
semanage permissive -a httpd_t


# Supervisord
yum install -y supervisor
systemctl enable supervisord
systemctl start supervisord
sed -i '4iWants=postgresql-9.6.service elasticsearch.service' /usr/lib/systemd/system/supervisord.service
sed -i '5iAfter=postgresql-9.6.service elasticsearch.service' /usr/lib/systemd/system/supervisord.service


# archive-frontend
rsync -avzhe ssh suitcase@app.archive.bbdomain.org:/sites/archive-frontend/ /sites/archive-frontend



# Static assets
rsync -avzhe ssh suitcase@app.archive.bbdomain.org:/sites/assets/ /sites/assets



# kmedia-mdb (SSR)
yum install -y git gcc-c++ make
curl --silent --location https://rpm.nodesource.com/setup_10.x | sudo bash -
yum install -y nodejs
curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo
yum install -y yarn

cd /sites/
git clone https://github.com/Bnei-Baruch/kmedia-mdb
cd /sites/kmedia-mdb/
yarn --frozen-lockfile
yarn cache clean
ln -s /sites/archive-frontend/ build
mkdir /sites/kmedia-mdb/logs
touch src/stylesheets/Kmedia.css
cp ${SCRIPT_BASE}/config/archive-ssr.env /sites/kmedia-mdb/.env



# archive-backend

# LibreOffice (required by archive-backend)
# https://www.libreoffice.org/download/download/
wget https://ftp.gwdg.de/pub/tdf/libreoffice/stable/6.0.6/rpm/x86_64/LibreOffice_6.0.6_Linux_x86-64_rpm.tar.gz
tar -xvf LibreOffice_6.0.6_Linux_x86-64_rpm.tar.gz
cd LibreOffice_6.0.6.2_Linux_x86-64_rpm/RPMS/
yum localinstall -y *.rpm

rsync -avzhe ssh --exclude 'logs/*' --exclude 'mdb-docx' suitcase@app.archive.bbdomain.org:/sites/archive-backend/ /sites/archive-backend
cp -f ${SCRIPT_BASE}/config/archive-backend.toml /sites/archive-backend/config.toml
cp ${SCRIPT_BASE}/script/bump_archive_backend.sh /sites/archive-backend/bump.sh
chmod +x /sites/archive-backend/bump.sh


# Imaginary
# https://github.com/h2non/imaginary

yum install -y expat-devel
curl -s https://raw.githubusercontent.com/h2non/bimg/master/preinstall.sh | sudo bash -
rsync -avzhe ssh --exclude 'logs/*' suitcase@app.archive.bbdomain.org:/sites/imaginary/ /sites/imaginary



# archive-unzip

# Python 3.6
yum install -y https://centos7.iuscommunity.org/ius-release.rpm
yum install -y python36u python36u-devel

# Install ffmpeg from sources
# https://trac.ffmpeg.org/wiki/CompilationGuide/Centos
yum install -y autoconf automake bzip2 cmake freetype-devel gcc gcc-c++ git libtool make mercurial pkgconfig zlib-devel openssl-devel
mkdir ~/ffmpeg_sources

# NASM
cd ~/ffmpeg_sources
curl -O -L http://www.nasm.us/pub/nasm/releasebuilds/2.13.02/nasm-2.13.02.tar.bz2
tar xjvf nasm-2.13.02.tar.bz2
cd nasm-2.13.02
./autogen.sh
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin"
make
make install

# Yasm
cd ~/ffmpeg_sources
curl -O -L http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz
tar xzvf yasm-1.3.0.tar.gz
cd yasm-1.3.0
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin"
make
make install

# libx264
cd ~/ffmpeg_sources
git clone --depth 1 http://git.videolan.org/git/x264
cd x264
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin" --enable-static
PATH="$HOME/bin:$PATH" make
make install

# ffmpeg
cd ~/ffmpeg_sources
curl -O -L https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2
tar xjvf ffmpeg-snapshot.tar.bz2
cd ffmpeg
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
  --prefix="$HOME/ffmpeg_build" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$HOME/ffmpeg_build/include" \
  --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
  --extra-libs=-lpthread \
  --bindir="$HOME/bin" \
  --enable-gpl \
  --enable-libfreetype \
  --enable-libx264 \
  --enable-openssl \
  --enable-nonfree
PATH="$HOME/bin:$PATH" make
make install
hash -r


# Pandoc
cd ~
wget https://github.com/jgm/pandoc/releases/download/2.1.3/pandoc-2.1.3-linux.tar.gz
tar xvzf pandoc-2.1.3-linux.tar.gz --strip-components 1 -C /usr/local/

yum install -y libtidy

# Make  virtualenv
cd /sites/
git clone https://github.com/Bnei-Baruch/archive-unzip
cd /sites/archive-unzip
python3.6 -m venv .
source bin/activate
yum install -y postgresql-devel
pip install -r requirements.txt
pip install uWSGI==2.0.15
mkdir logs
cp ${SCRIPT_BASE}/config/archive-unzip.ini app.ini



# mdb-links
rsync -avzhe ssh --exclude 'logs/*' suitcase@app.archive.bbdomain.org:/sites/mdb-links/ /sites/mdb-links
cp ${SCRIPT_BASE}/config/mdb-links.toml /sites/mdb-links/config.toml



# filer-backend
mkdir -p /sites/filer/{logs,indexes}
mkdir -p /root/.config
cp ${SCRIPT_BASE}/config/filer_storage.conf /root/.config/filer_storage.conf
echo "you need to get filer-backend executable into /sites/filer/filer-backend (probably from another suitcase)"



# mdb-fs
mkdir -p /sites/mdb-fs/logs
touch /mnt/storage/mdb_files/index
cp ${SCRIPT_BASE}/config/mdb-fs.toml /sites/mdb-fs/config.toml
cat <<EOT >> /sites/mdb-fs/config.toml
suitcase-id="${SUITCASE_ID}"
EOT
cp ${SCRIPT_BASE}/script/bump_mdb_fs.sh /sites/mdb-fs/bump.sh
chmod +x /sites/mdb-fs/bump.sh
echo "you need to get mdb-fs executable into /sites/mdb-fs/mdb-fs (manually or with bump.sh)"



# mdb
mkdir -p /sites/mdb/logs
cp ${SCRIPT_BASE}/config/mdb.toml /sites/mdb/config.toml
cp ${SCRIPT_BASE}/script/bump_mdb.sh /sites/mdb/bump.sh
chmod +x /sites/mdb/bump.sh
echo "you need to get mdb executable into /sites/mdb/mdb (manually or with bump.sh)"



# mdb admin ui
rsync -avzhe ssh suitcase@app.archive.bbdomain.org:/sites/admin/ /sites/admin
echo "this will get you nowhere. you need a suitcase version (teamcity build)"

# Final steps

# setup DNS
cat <<-EOT >> /etc/hosts
# Archive domain
127.0.0.1   archive
127.0.0.1   cdn.archive
127.0.0.1   files.archive
EOT

chown -R root:root /sites/
find /sites/assets/ -type d -exec chmod +755 {} \;

# bring all processes up
cp ${SCRIPT_BASE}/supervisord/*.ini /etc/supervisord.d
supervisorctl reread
supervisorctl update

# configure nginx
cp -f ${SCRIPT_BASE}/nginx/nginx.conf /etc/nginx
cp ${SCRIPT_BASE}/nginx/conf.d/*.conf /etc/nginx/conf.d
nginx -s reload

# setup scheduled jobs
cp ${SCRIPT_BASE}/cron/archive /etc/cron.d/
cp ${SCRIPT_BASE}/logrotate/archive /etc/logrotate.d

# bb-deployment ssh acceess - ci deploys (TeamCity)
echo "add bb-deployment ssh key to root's authorized_keys"
echo "deploy suitcase jobs of kmedia-mdb and mdb-admin to new suitcase"
