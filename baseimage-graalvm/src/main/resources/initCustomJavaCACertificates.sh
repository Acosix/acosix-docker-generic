#!/bin/bash

set -euo pipefail

# /etc/ssl/customCACerts normally does not exist - we allow custom CA certs to be mounted in to be added
if [ -d '/etc/ssl/customCACerts' ]
then
   echo "Processing custom CA certificates in /etc/ssl/customCACerts for Java cacerts bundle" > /proc/1/fd/1

   for file in /etc/ssl/customCACerts/*.pem
   do
      certName=`echo "$file" | cut -d '/' -f 5- | cut -d '.' -f 1`
      # in Java 11, this also supports -cacerts, but this script is used for both 8 and 11
      checkResult=`keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit -alias "${certName}" || true`
      if [[ ! $checkResult =~ ', trustedCertEntry,' ]]
      then
         keytool -import -trustcacerts -cacerts -storepass changeit -noprompt -alias "${certName}" -file "$file"
      fi
   done

   echo "Completed processing custom CA certificates in /etc/ssl/customCACerts for Java cacerts bundle" > /proc/1/fd/1
fi
