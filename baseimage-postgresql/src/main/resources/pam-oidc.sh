#!/bin/bash

set -euo pipefail

file_env() {
   local var="$1"
   local fileVar="${var}_FILE"
   local def="${2:-}"

   local val="$def"
   # Alfresco config variables can have dots in them - while allowed for environment variable identifiers, variable substitution in bash (and other shells) does not support it
   if [[ ${var} =~ '.' ]]; then
      local varV=$(env | grep "${var}=" | cut -d '=' -f 2- || true)
      local fileVarV=$(env | grep "${fileVar}=" | cut -d '=' -f 2- || true)

      if [ "${varV:-}" ] && [ "${fileVarV:-}" ]; then
         echo >&2 "Error: both $var and $fileVar are set (but are exclusive)"
         exit 1
      fi

      if [ "${varV:-}" ]; then
         val="${varV}"
      elif [ "${fileVarV:-}" ]; then
         val="$(< "${fileVarV}")"
      fi
      env -u "${fileVar}" > /dev/null
   else
      if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
         echo >&2 "Error: both $var and $fileVar are set (but are exclusive)"
         exit 1
      fi

      if [ "${!var:-}" ]; then
         val="${!var}"
      elif [ "${!fileVar:-}" ]; then
         val="$(< "${!fileVar}")"
      fi
      unset "$fileVar"
   fi

   echo "$val"
}

paddit() {
   local input=$1
   local l=$(echo -n $input | wc -c)
   while [ $(expr $l % 4) -ne 0 ]
   do
      local input="${input}="
      local l=$(echo -n $input | wc -c)
   done
   echo $input
}

# start env variables
# end env variables

AUTH_USER=${PAM_USER}

AUTH_ISSUER=${PAM_OIDC_ISSUER:-}
AUTH_TOKEN_URL=${PAM_OIDC_TOKEN_URL:-}
AUTH_TOKEN_INTROSPECTION_URL=${PAM_OIDC_TOKEN_INTROSPECTION_URL:-}
AUTH_CLIENT=${PAM_OIDC_CLIENT:-}
AUTH_CLIENT_SECRET=$(file_env PAM_OIDC_CLIENT_SECRET)

# note: as per https://www.postgresql.org/message-id/09512C4F-8CB9-4021-B455-EF4C4F0D55A0%40amazon.com a client (psql) may have limited / cut the password after X characters
# such would prevent use of OIDC token as passwords
# versions of psql released in 2021 or later could likely support long passwords 
AUTH_PASSWORD=$(cat - | tr '\0' '\n')

if [[ ! -z "$AUTH_CLIENT" && ! -z "$AUTH_CLIENT_SECRET" ]]
then
   tokenMatch=$(echo "$AUTH_PASSWORD" | grep -E "^[^\\.]+\\.[^\\.]+\\.[^\\.]+$" || true)

   if [[ ! -z "$AUTH_TOKEN_INTROSPECTION_URL" && ! -z "$AUTH_ISSUER" && "$tokenMatch" == "$AUTH_PASSWORD" ]]
   then

      read header payload signature <<< $(echo $AUTH_PASSWORD | tr [-_] [+/] | sed 's/\./ /g')
      payload=$(paddit $payload)
      apparentlyValid=$(echo $payload | base64 -d 2> /dev/null | jq ".azp == \"
${AUTH_CLIENT}\" and .typ == \"Bearer\"")

      if [[ $apparentlyValid == true ]]
      then

         ti=$(mktemp)
         status=$(curl $AUTH_TOKEN_INTROSPECTION_URL -d "token_type_hint=access_token&token=${AUTH_USER}" -u ${AUTH_CLIENT}:${AUTH_CLIENT_SECRET} -s -o $ti -w "%{http_code}")

         if [[ $status == 200 ]]
         then

            isValid=$(cat $ti | jq ".active and .username == \"${AUTH_USER}\"")

            if [[ isValid == true ]]
            then
               exit 0
            fi
         fi

         rm $ti
      fi
   elif [[ ! -z "$AUTH_TOKEN_URL" ]]
   then

      status=$(curl $AUTH_TOKEN_URL -d "grant_type=password&username=${AUTH_USER}&password=${AUTH_PASSWORD}" -u ${AUTH_CLIENT}:${AUTH_CLIENT_SECRET} -s -o /dev/null -w "%{http_code}")

      if [[ $status == 200 ]]
      then
         exit 0
      fi
   fi
fi

exit 1