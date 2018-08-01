#!/usr/bin/env bash
set +e
set -x

SCRIPT_BASE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Archive Suitcase install script
# On a fresh CentOS 7 minimal installation


# RPM Fusion and EPEL Repositories
yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm

# Setup Access over ssh
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

yum install -y https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/pgdg-centos96-9.6-3.noarch.rpm
yum install -y postgresql96 postgresql96-server
/usr/pgsql-9.6/bin/postgresql96-setup initdb
systemctl enable postgresql-9.6
sed -i 's/ident/trust/g' /var/lib/pgsql/9.6/data/pg_hba.conf
systemctl start postgresql-9.6
cat <<EOT > /root/.pgpass
${MDB_PGPASS}
EOT
chmod 0600 /root/.pgpass
#cp /root/.pgpass /home/archive
#chown archive:archive /home/archive/.pgpass

# Create ‘archive’ superuser
su postgres -c 'psql -c "CREATE USER archive WITH SUPERUSER;"'
su postgres -c 'psql -c "CREATE USER root WITH SUPERUSER;"'


# ElasticSearch
# https://www.elastic.co/guide/en/elasticsearch/reference/5.6/rpm.html
# https://www.elastic.co/guide/en/elasticsearch/reference/5.5/modules-snapshots.html

rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
cat <<EOT > /etc/yum.repos.d/elasticsearch.repo
[elasticsearch-5.x]
name=Elasticsearch repository for 5.x packages
baseurl=https://artifacts.elastic.co/packages/5.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOT
yum install -y elasticsearch-5.6.0-1
systemctl enable elasticsearch
systemctl start elasticsearch
cat <<EOT >> /etc/elasticsearch/elasticsearch.yml
bootstrap.memory_lock: true

# Disable system call filters
bootstrap.system_call_filter: false

# snapshot repo
path.repo: ["/backup/es"]
EOT
echo "exclude=elasticsearch*" >> /etc/yum.conf

systemctl restart elasticsearch
/usr/share/elasticsearch/bin/elasticsearch-plugin install analysis-icu
/usr/share/elasticsearch/bin/elasticsearch-plugin install analysis-phonetic
echo -e "y\n" | /usr/share/elasticsearch/bin/elasticsearch-plugin install https://bintray.com/synhershko/elasticsearch-analysis-hebrew/download_file?file_path=elasticsearch-analysis-hebrew-5.6.0.zip

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
sshpass -p "$SUITCASE_REMOTE_PASS" ssh-copy-id suitcase@app.archive.bbdomain.org
sshpass -p "$SUITCASE_REMOTE_PASS" ssh-copy-id suitcase@elastic.archive.bbdomain.org



# Setup and run first sync for MDB and ES
cp ${SCRIPT_BASE}/backup/sync.sh /backup
chmod +x /backup/sync.sh
exec /backup/sync.sh



# Nginx
yum install -y nginx
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



# archive-frontend
rsync -avzhe ssh suitcase@app.archive.bbdomain.org:/sites/archive-frontend/ /sites/archive-frontend



# Static assets
rsync -avzhe ssh suitcase@app.archive.bbdomain.org:/sites/assets/ /sites/assets



# kmedia-mdb (SSR)
yum install -y git nodejs gcc-c++ make
curl --silent --location https://rpm.nodesource.com/setup_9.x | sudo bash -
curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo
yum install -y yarn

cd /sites/
git clone https://github.com/Bnei-Baruch/kmedia-mdb
cd /sites/kmedia-mdb/
yarn --production
yarn cache clean
ln -s /sites/archive-frontend/ build
mkdir /sites/kmedia-mdb/logs
touch src/stylesheets/Kmedia.css
cp ${SCRIPT_BASE}/config/archive-ssr.env /sites/kmedia-mdb/.env



# archive-backend
rsync -avzhe ssh --exclude 'logs/*' --exclude 'mdb-docx' suitcase@app.archive.bbdomain.org:/sites/archive-backend/ /sites/archive-backend
cp -f ${SCRIPT_BASE}/config/archive-backend.toml /sites/archive-backend/config.toml



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


# Make  virtualenv
cd /sites/
git clone https://github.com/Bnei-Baruch/archive-unzip
cd /sites/archive-unzip
python3.6 -m venv .
source bin/activate
pip install -r requirements.txt
pip install uWSGI==2.0.15
mkdir logs
cp ${SCRIPT_BASE}/config/archive-unzip.ini app.ini



# mdb-links
rsync -avzhe ssh --exclude 'logs/*' suitcase@app.archive.bbdomain.org:/sites/mdb-links/ /sites/mdb-links
cp ${SCRIPT_BASE}/config/mdb-links.toml /sites/mdb-links/config.toml



# filer-backend
mkdir -p /sites/filer
mkdir -p /sites/.files/index
cp ${SCRIPT_BASE}/config/filer_storage.conf /root/.config/filer_storage.conf
echo "you need to get filer-backend executable into /sites/filer/filer-backend"



# mdb-fs
mkdir -p /sites/mdb-fs/{logs,root_storage}
touch /sites/mdb-fs/root_storage/index
cp ${SCRIPT_BASE}/config/mdb-fs.toml /sites/mdb-fs/config.toml
cat <<EOT >> /sites/mdb-fs/config.toml
suitcase-id="${SUITCASE_ID}"
EOT
echo "you need to get mdb-fs executable into /sites/mdb-fs/mdb-fs"



# Final steps

# setup DNS
cat <<EOT >> /etc/hosts
# Archive domain
127.0.0.1	archive
127.0.0.1	cdn.archive
127.0.0.1	files.archive
EOT


# bring all processes up
cp supervisord/*.ini /etc/supervisord.d
supervisorctl reread
supervisorctl update

# configure nginx
cp -f ${SCRIPT_BASE}/nginx/nginx.conf /etc/nginx
cp ${SCRIPT_BASE}/nginx/conf.d/*.conf /etc/nginx/conf.d
nginx -s reload

# setup scheduled jobs
cp ${SCRIPT_BASE}/cron/archive /etc/cron.d/
cp ${SCRIPT_BASE}/logrotate/archive /etc/logrotate.d