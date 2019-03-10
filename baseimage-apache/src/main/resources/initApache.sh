#!/bin/bash

set -euo pipefail

file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
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

PUBLIC_HOST=${PUBLIC_HOST:=host.example.com}
WEBMASTER_MAIL=${WEBMASTER_MAIL:=webmaster@host.example.com}
LETSENCRYPT_MAIL=${LETSENCRYPT_MAIL:=webmaster@host.example.com}

REGENERATE_PREDEFINED_DHPARAMS=${REGENERATE_PREDEFINED_DHPARAMS:=false}

BASE_SAMPLE_HOST=${BASE_SAMPLE_HOST:-}

ENABLE_SSL=${ENABLE_SSL:=true}
FORCE_SSL=${FORCE_SSL:=true}
USE_LETSENCRYPT=${USE_LETSENCRYPT:=true}

if [ ! -f '/var/lib/apache2/.initDone' ]
then
   mkdir -p /var/www/${PUBLIC_HOST}/html

   sed -i "s/^ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-available/security.conf
   sed -i "s/^ServerSignature On/ServerSignature Off/" /etc/apache2/conf-available/security.conf

   if [[ -z $(grep "^ServerName ${PUBLIC_HOST}" /etc/apache2/apache2.conf) ]]
   then
      sed -i "/# vim:/i ServerName ${PUBLIC_HOST}" /etc/apache2/apache2.conf
   fi

   if [ ! -f "/etc/apache2/sites-available/${PUBLIC_HOST}.conf" ]
   then
      if [ -f /etc/apache2/sites-available/host.conf ]
      then
         mv /etc/apache2/sites-available/host.conf /etc/apache2/sites-available/${PUBLIC_HOST}.conf
      elif [[ -n "${BASE_SAMPLE_HOST}" && -f "/etc/apache2/sites-available/${BASE_SAMPLE_HOST}.host.conf.sample" ]]
      then
         cp "/etc/apache2/sites-available/${BASE_SAMPLE_HOST}.host.conf.sample" /etc/apache2/sites-available/${PUBLIC_HOST}.conf
      elif [ -f /etc/apache2/sites-available/host.conf.sample ]
      then
         cp /etc/apache2/sites-available/host.conf.sample /etc/apache2/sites-available/${PUBLIC_HOST}.conf
      fi
   fi

   if [ ! -f "/etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf" ]
   then
      if [ -f /etc/apache2/sites-available/host.ssl.conf ]
      then
         mv /etc/apache2/sites-available/host.ssl.conf /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
      elif [[ -n "${BASE_SAMPLE_HOST}" && -f "/etc/apache2/sites-available/${BASE_SAMPLE_HOST}.host.ssl.conf.sample" ]]
      then
         cp "/etc/apache2/sites-available/${BASE_SAMPLE_HOST}.host.ssl.conf.sample" /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
      elif [ -f /etc/apache2/sites-available/host.ssl.conf.sample ]
      then
         cp /etc/apache2/sites-available/host.ssl.conf.sample /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
      fi
   fi

   if [ -f "/etc/apache2/sites-available/${PUBLIC_HOST}.conf" ]
   then
      sed -i "s/%HOST%/${PUBLIC_HOST}/g" /etc/apache2/sites-available/${PUBLIC_HOST}.conf
      sed -i "s/%WEBMASTER_ADDRESS%/${WEBMASTER_MAIL}/g" /etc/apache2/sites-available/${PUBLIC_HOST}.conf
   fi

   if [ -f "/etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf" ]
   then
      sed -i "s/%HOST%/${PUBLIC_HOST}/g" /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
      sed -i "s/%WEBMASTER_ADDRESS%/${WEBMASTER_MAIL}/g" /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
   fi
      
   # otherwise for will also cut on whitespace
   IFS=$'\n'
   for i in `env`
   do
      if [[ $i == VHOST_* ]]
      then
         echo "Processing environment variable $i" > /proc/1/fd/1
         key=`echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 2-`
         value=`echo "$i" | cut -d '=' -f 2-`

         if [ -f "/etc/apache2/sites-available/${PUBLIC_HOST}.conf" ]
         then
            sed -i "s/%${key}%/${value}/g" /etc/apache2/sites-available/${PUBLIC_HOST}.conf
         fi

         if [ -f "/etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf" ]
         then
            sed -i "s/%${key}%/${value}/g" /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
         fi
      fi
   done

   if [ ! -f "/etc/apache2/sites-enabled/${PUBLIC_HOST}.conf" ]
   then
      a2ensite ${PUBLIC_HOST}
   fi

   if [[ $ENABLE_SSL == true && ! -f "/etc/apache2/sites-enabled/${PUBLIC_HOST}.ssl.conf" ]]
   then
      # if new volume was mounted to /srv/apache2/ssl then we need to make sure folders exist before interacting with them
      mkdir -p /srv/apache2/ssl/certs

      if [[ -f '/srv/apache2/ssl/certs/dhparam.pem' ]]
      then
         rm /etc/ssl/certs/dhparam.pem
      else
         if [[ $REGENERATE_PREDEFINED_DHPARAMS == true ]]
         then
            openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096
         fi

         mv /etc/ssl/certs/dhparam.pem /srv/apache2/ssl/certs/
      fi
      ln -s /srv/apache2/ssl/certs/dhparam.pem /etc/ssl/certs/dhparam.pem

      if [[ $FORCE_SSL == true ]]
      then
         sed -i "s/#sslOnly#//g" /etc/apache2/sites-available/${PUBLIC_HOST}.conf
      fi

      if [[ $USE_LETSENCRYPT == true ]]
      then
         # we use / store SSL keys on volume to avoid re-issueing certificate too often (Let's Encrypt has limit of 20 certificates per week)
         mkdir -p /srv/apache2/ssl/letsencrypt

         MOST_RECENT_KEY_NUMBER=-1
         LE_ACCOUNT_EXISTS=false
         LE_ACCOUNT_ID=''
         LE_ACCOUNT_API=''
         for keyFile in /srv/apache2/ssl/certs/privkey*.pem
         do
            if [[ ${keyFile} != '/srv/apache2/ssl/certs/privkey*.pem' ]]
            then
               KEY_NUMBER=$(echo "${keyFile}" | sed -r 's/^.+\/privkey([0-9]*)\.pem$/\1/')
               if [ -n ${KEY_NUMBER} ]
               then
                  echo "Checking externally stored Let's Encrypt key files with number ${KEY_NUMBER}"

                  if [[ "${KEY_NUMBER}" -gt "${MOST_RECENT_KEY_NUMBER}" ]]
                  then
                     if [[ -f "/srv/apache2/ssl/certs/fullchain${KEY_NUMBER}.pem" && -f "/srv/apache2/ssl/certs/chain${KEY_NUMBER}.pem" && -f "/srv/apache2/ssl/certs/cert${KEY_NUMBER}.pem" ]]
                     then
                        echo "Externally stored Let's Encrypt key files with number ${KEY_NUMBER} form a complete set of cert, cert chains and private key"
                        MOST_RECENT_KEY_NUMBER=$KEY_NUMBER
                     fi
                  fi
               fi
            fi
         done

         if [[ -f "/srv/apache2/ssl/letsencrypt/${PUBLIC_HOST}.conf" && -f /srv/apache2/ssl/letsencrypt/meta.json && -f /srv/apache2/ssl/letsencrypt/private_key.json && -f /srv/apache2/ssl/letsencrypt/regr.json ]]
         then
            LE_ACCOUNT_EXISTS=true
            LE_ACCOUNT_ID=$(grep account /srv/apache2/ssl/letsencrypt/${PUBLIC_HOST}.conf | sed -r 's/account = (.+)/\1/')
            LE_ACCOUNT_API=$(less /srv/apache2/ssl/letsencrypt/regr.json | sed -r 's/.+"uri": "https:\/\/([^\/]+\.letsencrypt\.org)[^"]+".+/\1/')
            echo "Found Let's Encrypt account ${LE_ACCOUNT_ID} for API ${LE_ACCOUNT_API}"
         fi

         if [[ "${MOST_RECENT_KEY_NUMBER}" -gt "-1" && $LE_ACCOUNT_EXISTS ]]
         then
            echo "Mapping externally stored Let's Encrypt key and config files for continued use for ${PUBLIC_HOST}"
            mkdir -p /etc/letsencrypt/accounts/${LE_ACCOUNT_API}/directory/${LE_ACCOUNT_ID}
            mkdir -p /etc/letsencrypt/renewal
            mkdir -p /etc/letsencrypt/archive
            mkdir -p /etc/letsencrypt/live/${PUBLIC_HOST}

            ln -s ../../archive/${PUBLIC_HOST}/privkey${MOST_RECENT_KEY_NUMBER}.pem /etc/letsencrypt/live/${PUBLIC_HOST}/privkey.pem
            ln -s ../../archive/${PUBLIC_HOST}/chain${MOST_RECENT_KEY_NUMBER}.pem /etc/letsencrypt/live/${PUBLIC_HOST}/chain.pem
            ln -s ../../archive/${PUBLIC_HOST}/fullchain${MOST_RECENT_KEY_NUMBER}.pem /etc/letsencrypt/live/${PUBLIC_HOST}/fullchain.pem
            ln -s ../../archive/${PUBLIC_HOST}/cert${MOST_RECENT_KEY_NUMBER}.pem /etc/letsencrypt/live/${PUBLIC_HOST}/cert.pem
         else
            echo "Generating a new Let's Encrypt certificate for ${PUBLIC_HOST}"
            /usr/sbin/apache2ctl -k start
            certbot --apache --agree-tos -n -m ${LETSENCRYPT_MAIL} -d ${PUBLIC_HOST} certonly
            /usr/sbin/apache2ctl -k stop

            rm -f /srv/apache2/ssl/letsencrypt/*.json /srv/apache2/ssl/letsencrypt/*.conf
            
            LE_ACCOUNT_ID=$(grep account /etc/letsencrypt/renewal/${PUBLIC_HOST}.conf | sed -r 's/account = (.+)/\1/')
            LE_ACCOUNT_API=$(ls -A /etc/letsencrypt/accounts)
            
            mv /etc/letsencrypt/archive/${PUBLIC_HOST}/* /srv/apache2/ssl/certs/
            rm -rf /etc/letsencrypt/archive/${PUBLIC_HOST}

            mv /etc/letsencrypt/accounts/${LE_ACCOUNT_API}/directory/${LE_ACCOUNT_ID}/* /srv/apache2/ssl/letsencrypt/
            mv /etc/letsencrypt/renewal/${PUBLIC_HOST}.conf /srv/apache2/ssl/letsencrypt/
         fi

         sed -i "s/%CERTIFICATE_FILE%/\/etc\/letsencrypt\/live\/${PUBLIC_HOST}\/fullchain.pem/g" /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf
         sed -i "s/%CERTIFICATE_KEY%/\/etc\/letsencrypt\/live\/${PUBLIC_HOST}\/privkey.pem/g" /etc/apache2/sites-available/${PUBLIC_HOST}.ssl.conf

         ln -s /srv/apache2/ssl/certs /etc/letsencrypt/archive/${PUBLIC_HOST}
         ln -s /srv/apache2/ssl/letsencrypt/${PUBLIC_HOST}.conf /etc/letsencrypt/renewal/${PUBLIC_HOST}.conf
         ln -s /srv/apache2/ssl/letsencrypt/meta.json /etc/letsencrypt/accounts/${LE_ACCOUNT_API}/directory/${LE_ACCOUNT_ID}/meta.json
         ln -s /srv/apache2/ssl/letsencrypt/regr.json /etc/letsencrypt/accounts/${LE_ACCOUNT_API}/directory/${LE_ACCOUNT_ID}/regr.json
         ln -s /srv/apache2/ssl/letsencrypt/private_key.json /etc/letsencrypt/accounts/${LE_ACCOUNT_API}/directory/${LE_ACCOUNT_ID}/private_key.json
      fi
      # TODO Alternative SSL key handling

      chown -R www-data /srv/apache2/ssl/*

      a2enmod ssl
      a2ensite ${PUBLIC_HOST}.ssl
   fi

   chown -R www-data /var/www/html

   touch /var/lib/apache2/.initDone
fi