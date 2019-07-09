#!/usr/bin/env bash

set +e
set -x

VERSION=$1
echo "bump to version $VERSION"

curl -L https://github.com/Bnei-Baruch/archive-backend/releases/download/v$VERSION/archive-backend-$VERSION -o /sites/archive-backend/archive-backend-$VERSION
chmod +x /sites/archive-backend/archive-backend-$VERSION 
ln -sf /sites/archive-backend/archive-backend-$VERSION /sites/archive-backend/archive-backend
supervisorctl restart archive

