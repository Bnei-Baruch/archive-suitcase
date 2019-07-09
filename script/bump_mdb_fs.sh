#!/usr/bin/env bash

set +e
set -x

VERSION=$1
echo "bump to version $VERSION"

curl -L https://github.com/Bnei-Baruch/mdb-fs/releases/download/v$VERSION/mdb-fs-$VERSION -o /sites/mdb-fs/mdb-fs-$VERSION
chmod +x /sites/mdb-fs/mdb-fs-$VERSION 
ln -sf /sites/mdb-fs/mdb-fs-$VERSION /sites/mdb-fs/mdb-fs
supervisorctl restart mdb-fs

