#!/usr/bin/env bash
set +e
set -x

# MDB (postgres)
TIMESTAMP="$(date '+%Y%m%d%H%M%S')"
DUMP_FILE="/backup/mdb/mdb_dump_$TIMESTAMP.sql"

pg_dump -h pgsql.mdb.bbdomain.org -U readonly --no-owner --create --clean --format=plain -d mdb --file="${DUMP_FILE}"

supervisorctl stop all
psql -d postgres -f "${DUMP_FILE}"
supervisorctl start all

gzip ${DUMP_FILE}
find "/backup/mdb" -type f -mtime +7 -exec rm -rf {} \;

# Elasticsearch
rsync -avzhe ssh --delete suitcase@elastic.archive.bbdomain.org:/backup/es/ /backup/es
curl -XPOST localhost:9200/_all/_close
sleep 5s
curl -XPOST localhost:9200/_snapshot/backup/full/_restore