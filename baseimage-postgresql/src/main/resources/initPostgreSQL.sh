#!/bin/bash

set -e

PG_DATA=${PG_DATA:-/srv/postgresql/data}
PG_INIT_SCRIPTS=${PG_INIT_SCRIPTS:-/srv/postgresql/init}

PG_USER=${PG_USER:-postgres}
PG_DB=${PG_USER:=${PG_USER}}

PG_VERSION="$(ls -A --ignore=.* /usr/lib/postgresql)"

if [ ! -f "/var/lib/.postgresInitDone" ]
then

   echo -e "source s_postgreqsl { file("/var/log/postgresql/postgresql-${PG_VERSION}-main.log" follow-freq(1)); };\nlog { source(s_postgreqsl); destination(d_stdout); };" > /etc/syslog-ng/conf.d/postgresql-ng.conf

   for i in `env`
    do
        if [[ $i == PGCONF_* ]]
      then
            key=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 2-`
         value=`echo $i | cut -d '=' -f 2-`
         
         if grep --quiet "^${key}\s*=" "/etc/postgresql/${PG_VERSION}/main/postgresql.conf"; then
            sed -i "s/^${key}\s*=.*/${key}=${value}/" "/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
         else
            echo "${key}=${value}" >> "/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
         fi
        fi
    done
   
   if [[ ! -d "${PG_DATA}" ]]
   then
      mkdir -p "${PG_DATA}"
      chown -R postgres:postgres "${PG_DATA}"
      chmod 0700 "${PG_DATA}"
   fi
   
   if [[ -z "$(ls -A "${PG_DATA}")" ]]
   then
      su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/initdb -D ${PG_DATA}"
   
      if [[ "${PG_PASS}" ]]
      then
         PASS="PASSWORD '${PG_PASS}'"
         AUTH=md5
      else
         PASS=""
         AUTH=trust
      fi

      if [ "${PG_USER}" != 'postgres' ]; then
         echo "Creating user ${PG_USER}"
         USER_OP=CREATE
      else
         echo "Altering user ${PG_USER} (password)"
         USER_OP=ALTER
      fi
      USER_SQL="${USER_OP} USER ${PG_USER} WITH SUPERUSER ${PASS};"
      echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -jE -D ${PG_DATA}"

      if [ "${PG_DB}" != 'postgres' ]; then
         echo "Creating database ${PG_DB}"
         CREATE_SQL="CREATE DATABASE ${PG_DB} ENCODING = 'UTF8' OWNER = ${PG_USER};"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -jE -D ${PG_DATA}"
      fi

      if [[ -n "$(ls -A "${PG_INIT_SCRIPTS}")" ]]
      then
         su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl -D ${PG_DATA} -l /var/log/postgresql/postgresql-${PG_VERSION}-main.log -o \"-c listen_addresses=''\" -w start"

         echo "Running any database initialisation scripts"
         for script in ${PG_INIT_SCRIPTS}/*.sql
         do
            "/usr/lib/postgresql/${PG_VERSION}/bin/psql" --username "${PG_USER}" --dbname "${PG_DB}" < "$script"
         done

         su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl -D ${PG_DATA} -m fast -w stop"
      fi

      echo "host all all 0.0.0.0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"
      echo "host all all ::0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"
   fi

   sed -ri "s/^#(listen_addresses\s*=\s*)\S+/\1'*'/" "${PG_DATA}/postgresql.conf"

   touch "/var/lib/.postgresInitDone"
fi