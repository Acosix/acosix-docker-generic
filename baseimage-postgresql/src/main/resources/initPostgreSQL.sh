#!/bin/bash

set -euo pipefail

file_env() {
   local var="$1"
   local fileVar="${var}_FILE"
   local def="${2:-}"
   if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
      echo >&2 "Error: both $var and $fileVar are set (but are exclusive)"
      exit 1
   fi
   local val="$def"
   if [ "${!var:-}" ]; then
      val="${!var}"
   elif [ "${!fileVar:-}" ]; then
      val="$(< "${!fileVar}")"
   fi
   unset "$fileVar"
   echo "$val"
}

setInConfigFile() {
   local fileName="$1"
   local key="$2"
   local value="${3:=''}"

   # escape typical special characters in key / value (. and / for dot-separated keys or path values)
   regexSafeKey=`echo "$key" | sed -r 's/\\//\\\\\//g' | sed -r 's/\\./\\\\\./g'`
   replacementSafeKey=`echo "$key" | sed -r 's/\\//\\\\\//g' | sed -r 's/&/\\\\&/g'`
   replacementSafeValue=`echo "$value" | sed -r 's/\\//\\\\\//g' | sed -r 's/&/\\\\&/g'`

   if grep --quiet -E "^#?${regexSafeKey}=" ${fileName}; then
      sed -i -r "s/^#?${regexSafeKey}=.*/${replacementSafeKey}=${replacementSafeValue}/" ${fileName}
   else
      echo "${key}=${value}" >> ${fileName}
   fi
}

PG_DATA=${PG_DATA:-/srv/postgresql/data}
PG_INIT_SCRIPTS=${PG_INIT_SCRIPTS:-/srv/postgresql/init}

# these are only for the root / main admin user
PG_USER=${PG_USER:-postgres}
PG_DB=${PG_USER:=${PG_USER}}
PG_PASS=$(file_env PG_PASS)

PG_VERSION="$(ls -A --ignore=.* /usr/lib/postgresql)"

if [ ! -f "/var/lib/.postgresInitDone" ]
then

   echo -e "source s_postgreqsl { file("/var/log/postgresql/postgresql-${PG_VERSION}-main.log" follow-freq(1)); };\nlog { source(s_postgreqsl); destination(d_stdout); };" > /etc/syslog-ng/conf.d/postgresql-ng.conf

   IFS=$'\n'
   for i in `env`
   do
      if [[ $i == PGCONF_* ]]
      then
         key=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 2-`
         value=`echo $i | cut -d '=' -f 2-`

         setInConfigFile "/etc/postgresql/${PG_VERSION}/main/postgresql.conf" ${key} ${value}
      fi
   done
   
   if [[ ! -d "${PG_DATA}" ]]
   then
      mkdir -p $PG_DATA
   fi
   chown -R postgres:postgres $PG_DATA
   chmod 0700 $PG_DATA
   
   if [[ -z "$(ls -A "${PG_DATA}")" ]]
   then
      su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/initdb -D ${PG_DATA}"
   
      if [[ ! -z "${PG_PASS}" ]]
      then
         PASS="PASSWORD '${PG_PASS}'"
         AUTH=md5
      else
         PASS=""
         AUTH=trust
      fi

      if [ "${PG_USER}" != 'postgres' ]; then
         echo "Creating user ${PG_USER}" > /proc/1/fd/1
         USER_OP=CREATE
      else
         echo "Altering user ${PG_USER} (password)" > /proc/1/fd/1
         USER_OP=ALTER
      fi
      USER_SQL="${USER_OP} USER ${PG_USER} WITH SUPERUSER ${PASS};"
      echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null

      if [ "${PG_DB}" != 'postgres' ]; then
         echo "Creating database ${PG_DB}" > /proc/1/fd/1
         CREATE_SQL="CREATE DATABASE ${PG_DB} ENCODING = 'UTF8' OWNER = ${PG_USER};"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
         CREATE_SQL="CREATE SCHEMA ${PG_DB} AUTHORIZATION ${PG_USER};"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${PG_DB}" > /dev/null
         CREATE_SQL="ALTER DATABASE ${PG_DB} SET search_path TO ${PG_DB}, public;"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null

         echo "host ${PG_DB} ${PG_USER} 0.0.0.0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"
         echo "host ${PG_DB} ${PG_USER} ::0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"

      elif [ "${PG_USER}" != 'postgres' ]; then

         echo "host all ${PG_USER} 0.0.0.0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"
         echo "host all ${PG_USER} ::0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"

      fi

      if [ "${PG_USER}" = 'postgres' ]; then
         echo "host all postgres 0.0.0.0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"
         echo "host all postgres ::0/0 ${AUTH}" >> "${PG_DATA}/pg_hba.conf"
      fi

      # 1st loop: create users
      IFS=$'\n'
      for i in `env`
      do
         if [[ $i == PG_USER_* ]]
         then
            user=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-`
            pass=$(file_env "PG_PASS_${user}")

            echo "Creating user ${user}" > /proc/1/fd/1

            USER_SQL="CREATE USER ${user} NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '${pass}';"
            echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
         fi
      done

      # 2nd loop: create databases
      IFS=$'\n'
      for i in `env`
      do
         if [[ $i == PG_DB_* ]]
         then
            db=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-`
            owner=`echo "$i" | cut -d '=' -f 2-`

            echo "Creating database ${db}" > /proc/1/fd/1

            CREATE_SQL="CREATE DATABASE ${db} ENCODING = 'UTF8'"
            if [[ ! -z "${owner}" ]]
            then
               CREATE_SQL="${CREATE_SQL} OWNER = ${owner};"
            else
               CREATE_SQL="${CREATE_SQL};"
            fi
            echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
            CREATE_SQL="CREATE SCHEMA ${db}"
            if [[ ! -z "${owner}" ]]
            then
               CREATE_SQL="${CREATE_SQL} AUTHORIZATION ${owner};"
            else
               CREATE_SQL="${CREATE_SQL};"
            fi
            echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
            CREATE_SQL="ALTER DATABASE ${db} SET search_path TO ${db}, public;"
            echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null

            if [ "${owner}" != 'postgres' -a "${owner}" != "${PG_USER}" ]; then

               echo "Setting up client access for owner ${owner} to ${db}" > /proc/1/fd/1

               echo "host ${db} ${owner} 0.0.0.0/0 md5" >> "${PG_DATA}/pg_hba.conf"
               echo "host ${db} ${owner} ::0/0 md5" >> "${PG_DATA}/pg_hba.conf"
            fi
         fi
      done

      # 3rd loop: setup client access control for users
      IFS=$'\n'
      for i in `env`
      do
         if [[ $i == PG_USER_* ]]
         then
            user=`echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 3-`
            dbs=`echo "$i" | cut -d '=' -f 2-`

            if [[ ! -z "${dbs}" ]]
            then
               echo "Setting up client access for ${user} to ${dbs}" > /proc/1/fd/1

               IFS=$','
               for db in ${dbs}
               do
                  echo "host ${db} ${user} 0.0.0.0/0 md5" >> "${PG_DATA}/pg_hba.conf"
                  echo "host ${db} ${user} ::0/0 md5" >> "${PG_DATA}/pg_hba.conf"
               done
            fi
            IFS=$'\n'
         fi
      done

      # 4th loop: user-db privileges
      IFS=$'\n'
      for i in `env`
      do
         if [[ $i == PG_PRIVILEGE_* ]]
         then
            user=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-`
            db=`echo "$i" | cut -d '=' -f 2- | cut -d ':' -f 1`
            mode=`echo "$i" | cut -d '=' -f 2- | cut -d ':' -f 2-`

            echo "Setting up access privilege for user ${user} to ${db} in mode ${mode}" > /proc/1/fd/1

            if [ "${mode}" = 'read' ]; then
               GRANT_SQL="GRANT CONNECT ON DATABASE ${db} TO ${user};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
               GRANT_SQL="GRANT USAGE ON SCHEMA ${db} TO ${user};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
               GRANT_SQL="GRANT SELECT ON ALL SEQUENCES IN SCHEMA ${db} TO ${user};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
               GRANT_SQL="GRANT SELECT ON ALL TABLES IN SCHEMA ${db} TO ${user};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null

               # future object grants
               GRANT_SQL="ALTER DEFAULT PRIVILEGES IN SCHEMA ${db} GRANT SELECT ON TABLES TO ${user};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
               GRANT_SQL="ALTER DEFAULT PRIVILEGES IN SCHEMA ${db} GRANT SELECT ON SEQUENCES TO ${user};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null

            elif [ "${mode}" = 'full' -o "${mode}" = 'write' ]; then

               GRANT_OPT=""
               if [ "${mode}" = 'full' ]; then
                  GRANT_OPT=" WITH GRANT OPTION"
               fi

               GRANT_SQL="GRANT ALL ON DATABASE ${db} TO ${user}${GRANT_OPT};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
               GRANT_SQL="GRANT ALL ON SCHEMA ${db} TO ${user}${GRANT_OPT};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
               GRANT_SQL="GRANT ALL ON ALL SEQUENCES IN SCHEMA ${db} TO ${user}${GRANT_OPT};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
               GRANT_SQL="GRANT ALL ON ALL TABLES IN SCHEMA ${db} TO ${user}${GRANT_OPT};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null

               # future object grants
               GRANT_SQL="ALTER DEFAULT PRIVILEGES IN SCHEMA ${db} GRANT ALL ON TABLES TO ${user}${GRANT_OPT};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
               GRANT_SQL="ALTER DEFAULT PRIVILEGES IN SCHEMA ${db} GRANT ALL ON SEQUENCES TO ${user}${GRANT_OPT};"
               echo ${GRANT_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
            fi
         fi
      done

      mkdir -p ${PG_INIT_SCRIPTS}
      if [[ -n "$(ls -A "${PG_INIT_SCRIPTS}")" ]]
      then
         su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl -D ${PG_DATA} -l /var/log/postgresql/postgresql-${PG_VERSION}-main.log -o \"-c listen_addresses=''\" -w start"

         echo "Running any database initialisation scripts" > /proc/1/fd/1
         for script in ${PG_INIT_SCRIPTS}/*.sql
         do
            "/usr/lib/postgresql/${PG_VERSION}/bin/psql" --username "${PG_USER}" --dbname "${PG_DB}" < "$script"
         done

         su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/pg_ctl -D ${PG_DATA} -m fast -w stop"
      fi 
   fi

   sed -ri "s/^#(listen_addresses\s*=\s*)\S+/\1'*'/" "${PG_DATA}/postgresql.conf"

   touch "/var/lib/.postgresInitDone"
fi