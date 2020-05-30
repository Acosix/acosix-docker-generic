#!/bin/bash

set -euo pipefail

if [ ! -f '/etc/postfix/.postfixInitDone' ]
then

   echo "Processing environment variables for postfix main.cf" > /proc/1/fd/1
   # otherwise for will also cut on whitespace
   IFS=$'\n'
   for i in `env`
   do
      if [[ $i == POSTFIX-MAIN_* ]]
      then
         echo "Processing environment variable $i" > /proc/1/fd/1
         key=`echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 2-`
         value=`echo "$i" | cut -d '=' -f 2-`

         if [[ $key == mydomain ]]
         then
            echo $value > /etc/mailname
         fi

         postconf -e "$key = $value"
      fi

      if [[ $i == POSTFIX-ALIAS_* ]]
      then
         echo "Processing environment variable $i" > /proc/1/fd/1
         key=`echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 2-`
         value=`echo "$i" | cut -d '=' -f 2-`

         if grep --quiet "^${key}:" /etc/aliases; then
            # encode any / in $value to avoid interference with sed (note: sh collapses 2 \'s into 1)
            value=`echo "$value" | sed -r 's/\\//\\\\\//g' | sed -r 's/&/\\\\&/g'`
            sed -i "s/^${key}:.*/${key}: ${value}/" /etc/aliases
         else
            echo "${key}: ${value}" >> /etc/aliases
         fi
    
         newaliases
      fi
      
      if [[ $i == POSTFIX-MAP_* ]]
      then
         echo "Processing environment variable $i" > /proc/1/fd/1
         filename=`echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 2`
         key=`echo "$i" | cut -d '=' -f 1 | cut -d '_' -f 3-`
         value=`echo "$i" | cut -d '=' -f 2-`

         if [ -f "/etc/postfix/$filename" ]
         then
            if grep --quiet "^${key}\s" /etc/postfix/$filename; then
               # encode any / in $value to avoid interference with sed (note: sh collapses 2 \'s into 1)
               value=`echo "$value" | sed -r 's/\\//\\\\\//g' | sed -r 's/&/\\\\&/g'`
               sed -i "s/^${key}.*/${key} ${value}/" /etc/postfix/$filename
            else
               echo "${key} ${value}" >> /etc/postfix/$filename
            fi
         else
            echo "${key} ${value}" >> /etc/postfix/$filename
         fi

         postmap /etc/postfix/$filename
      fi
   done

   touch /etc/postfix/.postfixInitDone
fi

# Deviation from baseimage standard usage: start postfix in init script
# there is no binary we can call in a blocking way for use in a regular /etc/service/postfix/run start script
service postfix start