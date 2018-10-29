#!/bin/sh

set -e

PG_DATA=${PG_DATA:-/srv/postgresql/data}
PG_VERSION="$(ls -A --ignore=.* /usr/lib/postgresql)"

exec /sbin/setuser postgres "/usr/lib/postgresql/${PG_VERSION}/bin/postgres" -D "${PG_DATA}" > "/var/log/postgresql/postgresql-${PG_VERSION}-main.log" 2>&1