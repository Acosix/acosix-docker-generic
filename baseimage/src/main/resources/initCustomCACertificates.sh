#!/bin/bash

set -euo pipefail

# /etc/ssl/customCACerts normally does not exist - we allow custom CA certs to be mounted in to be added
if [ -d '/etc/ssl/customCACerts' ]
then
   echo "Processing custom CA certificates in /etc/ssl/customCACerts for OS certificates bundle" > /proc/1/fd/1

   if [ ! -d "$HOME/.pki/nssdb" ]
   then
      mkdir -p $HOME/.pki/nssdb
      certutil -d $HOME/.pki/nssdb -N
   fi

   cp /etc/ssl/customCACerts/*.pem /etc/ssl/certs/
   for file in /etc/ssl/customCACerts/*.pem
   do
      certName=`echo "$file" | cut -d '/' -f 5-`
      if [ -e "/etc/ssl/certs/${certName}" ]
      then
         hash=`openssl x509 -hash -noout -in "$file"`
         ln -s "/etc/ssl/certs/${certName}" /etc/ssl/certs/${hash}.0
         cat "/etc/ssl/certs/${certName}" >> /etc/ssl/certs/ca-certificates.crt
         certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "${certName}" -i "/etc/ssl/certs/${certName}"
      fi
   done

   echo "Completed processing custom CA certificates in /etc/ssl/customCACerts for OS certificates bundle" > /proc/1/fd/1
fi
