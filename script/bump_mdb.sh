#!/usr/bin/env bash

set +e
set -x

VERSION=$1
echo "bump to version $VERSION"

curl -L https://github.com/Bnei-Baruch/mdb/releases/download/v$VERSION/mdb-$VERSION -o /sites/mdb/mdb-$VERSION
chmod +x /sites/mdb/mdb-$VERSION 
ln -sf /sites/mdb/mdb-$VERSION /sites/mdb/mdb
supervisorctl restart mdb

