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
   local value="${3:-}"

   # escape typical special characters in key / value (. and / for dot-separated keys or path values)
   # note: & must be double escaped as regular interpolation unescapes it
   regexSafeKey=$(echo "$key" | sed -r 's#/#\\\\/#g' | sed -r 's#\.#\\\\.#g')
   replacementSafeValue=$(echo "$value" | sed -r 's#/#\\\\/#g' | sed -r 's#&#\\&#g')

   if grep --quiet -E "^#?${regexSafeKey}\s*=" ${fileName}; then
      sed -ri "s/^#?(${regexSafeKey}\s*=)[^#$]*/\1${replacementSafeValue} /" ${fileName}
   else
      echo "${key} = ${value}" >> ${fileName}
   fi
}

PG_DATA=${PG_DATA:-/srv/postgresql/data}
PG_INIT_SCRIPTS=${PG_INIT_SCRIPTS:-/srv/postgresql/init}

# these are only for the root / main admin user
PG_USER=${PG_USER:-postgres}
PG_DB=${PG_USER:=${PG_USER}}
PG_PASS=$(file_env PG_PASS)

if [[ ! -z "${PG_PASS}" ]]
then
   PASS="PASSWORD '${PG_PASS}'"
else
   PASS=""
fi

PG_VERSION="$(ls -A --ignore=.* /usr/lib/postgresql)"

PG_USE_PAM=${PG_USE_PAM:-false}
PG_USE_PAM_OIDC=${PG_USE_PAM_OIDC:-false}
PG_FORCE_SSL=${PG_FORCE_SSL:-false}

# Initial setup
if [ ! -f "/var/lib/.postgresInitDone" ]
then

   if [[ ! -d "${PG_DATA}" ]]
   then
      mkdir -p $PG_DATA
   fi
   chown -R postgres:postgres $PG_DATA
   chmod 0700 $PG_DATA

   # TODO Support version upgrade
   if [[ -z "$(ls -A "${PG_DATA}")" ]]
   then
      su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/initdb -D ${PG_DATA}"

      cp "${PG_DATA}/postgresql.conf" "${PG_DATA}/postgresql.conf.default"
      cp "${PG_DATA}/pg_hba.conf" "${PG_DATA}/pg_hba.conf.default"

      if [[ "${PG_USER}" != 'postgres' ]]
      then
         echo "Creating user ${PG_USER}" > /proc/1/fd/1
         USER_SQL="CREATE USER ${PG_USER} WITH SUPERUSER ${PASS};"
         echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
      fi

      if [[ "${PG_DB}" != 'postgres' ]]
      then
         echo "Creating database ${PG_DB}" > /proc/1/fd/1
         CREATE_SQL="CREATE DATABASE ${PG_DB} ENCODING = 'UTF8' OWNER = ${PG_USER};"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
         CREATE_SQL="CREATE SCHEMA ${PG_DB} AUTHORIZATION ${PG_USER};"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${PG_DB}" > /dev/null
         CREATE_SQL="ALTER DATABASE ${PG_DB} SET search_path TO ${PG_DB}, public;"
         echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null
      fi

      PERM_SQL='REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM public;'
      echo ${PERM_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" template1 > /dev/null
      PERM_SQL='REVOKE USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public FROM public;'
      echo ${PERM_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" template1 > /dev/null

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

   # Reset config so any previous PGCONF_* based settings no longer present are reset
   cp "${PG_DATA}/postgresql.conf.default" "${PG_DATA}/postgresql.conf"
   IFS=$'\n'
   for i in $(env)
   do
      if [[ $i == PGCONF_* ]]
      then
         key=$(echo $i | cut -d '=' -f 1 | cut -d '_' -f 2-)
         value=$(echo $i | cut -d '=' -f 2-)

         if [[ $key == *_FILE ]]
         then
            value="$(< "${value}")"
            key=$(echo "$key" | sed -r 's/_FILE$//')
         fi

         setInConfigFile "${PG_DATA}/postgresql.conf" ${key} ${value}
      fi
   done

   # always use the more secure password encryption
   setInConfigFile "${PG_DATA}/postgresql.conf" password_encryption scram-sha-256
   sed -ri "s/^#(listen_addresses\s*=\s*)\S+/\1'*'/" "${PG_DATA}/postgresql.conf"

   # Reset access config so any previous settings that may no longer be applicable are reset
   cp "${PG_DATA}/pg_hba.conf.default" "${PG_DATA}/pg_hba.conf"

   # Update main user's password
   if [[ ! -z "$PG_PASS" ]]
   then
      echo "Setting/updating password for user ${PG_USER}" > /proc/1/fd/1
      USER_SQL="ALTER USER ${PG_USER} WITH SUPERUSER ${PASS};"
      echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null

      if [[ "${PG_FORCE_SSL}" == true ]]
      then
         echo "hostssl all ${PG_USER} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
         echo "hostssl all ${PG_USER} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
      else
         echo "host all ${PG_USER} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
         echo "host all ${PG_USER} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
      fi
   fi

   # 1st loop: create users or update passwords
   IFS=$'\n'
   for i in $(env)
   do
      if [[ $i == PG_USER_* ]]
      then
         user=$(echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-)

         if [[ "${user}" != 'postgres' ]] && [[ "${user}" != "${PG_USER}" ]]
         then
            userPass=$(file_env "PG_PASS_${user}")

            sqlResult=$(echo "SELECT COUNT(*) AS C FROM pg_catalog.pg_user WHERE usename = '${user}';" | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" | tail -n 3 | head -n 1 | cut -d '"' -f 2)
            if [[ $sqlResult == '1' ]]
            then
               if [[ ! -z "${userPass}" ]]
               then
                  echo "Setting/updating password for user ${user}" > /proc/1/fd/1
                  USER_SQL="ALTER USER ${user} PASSWORD '${userPass}';"
                  echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null

                  if [[ "${PG_FORCE_SSL}" == true ]]
                  then
                     echo "hostssl all ${user} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                     echo "hostssl all ${user} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                  else
                     echo "host all ${user} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                     echo "host all ${user} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                  fi
               fi
            else
               if [[ ! -z "${userPass}" ]]
               then
                  PASS="PASSWORD '${userPass}'"
               else
                  PASS=""
               fi

               echo "Creating user ${user}" > /proc/1/fd/1
               USER_SQL="CREATE USER ${user} NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION ${PASS};"
               echo ${USER_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" > /dev/null

               # remote access only with password
               if [[ ! -z "${userPass}" ]]
               then
                  if [[ "${PG_FORCE_SSL}" == true ]]
                  then
                     echo "hostssl all ${user} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                     echo "hostssl all ${user} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                  else
                     echo "host all ${user} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                     echo "host all ${user} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                  fi
               fi
            fi
         fi
      fi
   done

   # 2nd loop: create databases (no update owner support)
   IFS=$'\n'
   for i in $(env)
   do
      if [[ $i == PG_DB_* ]]
      then
         db=$(echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-)
         owner=$(echo "$i" | cut -d '=' -f 2-)

         sqlResult=$(echo "SELECT COUNT(*) AS C FROM pg_catalog.pg_database WHERE datname = '${db}';" | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA}" | tail -n 3 | head -n 1 | cut -d '"' -f 2)
         if [[ $sqlResult == '0' ]]
         then
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
         fi
      fi
   done

   # 3rd loop: setup extensions
   IFS=$'\n'
   for i in $(env)
   do
      if [[ $i == PG_DB_* ]]
      then
         db=$(echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-)
         key="PG_EXT_$db"
         extensions=${!key:-}
         if [[ ! -z "$extensions" ]]
         then
            IFS=$','
            for extension in ${extensions}
            do
               CREATE_SQL="CREATE EXTENSION IF NOT EXISTS \"$extension\";"
               echo ${CREATE_SQL} | su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/postgres --single -j -D ${PG_DATA} ${db}" > /dev/null
            done
         fi
      fi
   done

   # 4th loop: process client access control for users
   IFS=$'\n'
   for i in $(env)
   do
      if [[ $i == PG_USER_* ]]
      then
         user=$(echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 3-)
         dbs=$(echo "$i" | cut -d '=' -f 2-)

         if [[ ! -z "${dbs}" ]]
         then
            echo "Processing client access for ${user} to ${dbs}" > /proc/1/fd/1

            IFS=$','
            for db in ${dbs}
            do
               if [[ "${PG_FORCE_SSL}" == true ]]
               then
                  echo "hostssl ${db} ${user} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                  echo "hostssl ${db} ${user} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
               else
                  echo "host ${db} ${user} 0.0.0.0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
                  echo "host ${db} ${user} ::0/0 scram-sha-256" >> "${PG_DATA}/pg_hba.conf"
               fi
            done
         fi
         IFS=$'\n'
      fi
   done

   # 5th loop: user-db privileges
   IFS=$'\n'
   for i in $(env)
   do
      if [[ $i == PG_PRIVILEGE_* ]]
      then
         user=$(echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-)
         db=$(echo "$i" | cut -d '=' -f 2- | cut -d ':' -f 1)
         mode=$(echo "$i" | cut -d '=' -f 2- | cut -d ':' -f 2-)

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

   if [[ "${PG_USE_PAM}" == true ]]
   then
      if [[ "${PG_FORCE_SSL}" == true ]]
      then
         echo "hostssl all all 0.0.0.0/0 pam" >> "${PG_DATA}/pg_hba.conf"
         echo "hostssl all all ::0/0 pam" >> "${PG_DATA}/pg_hba.conf"
      else
         echo "host all all 0.0.0.0/0 pam" >> "${PG_DATA}/pg_hba.conf"
         echo "host all all ::0/0 pam" >> "${PG_DATA}/pg_hba.conf"
      fi

      if [[ "${PG_USE_PAM_OIDC}" == true ]]
      then
         sed -i '/# end rules/i auth sufficient pam_exec.so expose_authtok type=auth /usr/lib/pam-oidc.sh' /etc/pam.d/postgresql

         # PAM script does not have access to env variables, so we inject them here
         sed -i "/# end env variables/i PAM_OIDC_CLIENT_SECRET_FILE=${PAM_OIDC_CLIENT_SECRET_FILE:-}" /usr/lib/pam-oidc.sh
         sed -i "/# end env variables/i PAM_OIDC_CLIENT_SECRET=${PAM_OIDC_CLIENT_SECRET:-}" /usr/lib/pam-oidc.sh
         sed -i "/# end env variables/i PAM_OIDC_CLIENT=${PAM_OIDC_CLIENT:-}" /usr/lib/pam-oidc.sh
         sed -i "/# end env variables/i PAM_OIDC_TOKEN_INTROSPECTION_URL=${PAM_OIDC_TOKEN_INTROSPECTION_URL:-}" /usr/lib/pam-oidc.sh
         sed -i "/# end env variables/i PAM_OIDC_TOKEN_URL=${PAM_OIDC_TOKEN_URL:-}" /usr/lib/pam-oidc.sh
         sed -i "/# end env variables/i PAM_OIDC_ISSUER=${PAM_OIDC_ISSUER:-}" /usr/lib/pam-oidc.sh
      fi
   fi

   if [[ -f "/var/log/postgresql/postgresql-${PG_VERSION}-main.log" ]]
   then
      cat /var/log/postgresql/postgresql-${PG_VERSION}-main.log > /proc/1/fd/1
   fi

   touch "/var/lib/.postgresInitDone"
fi
