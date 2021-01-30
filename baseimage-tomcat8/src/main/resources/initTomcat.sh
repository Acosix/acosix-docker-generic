#!/bin/bash

set -euo pipefail

DEBUG=${DEBUG:-false}
DEBUG_PORT=${DEBUG_PORT:-8000}

ENABLE_PROXY=${ENABLE_PROXY:-true}
PROXY_NAME=${PROXY_NAME:-localhost}
PROXY_PORT=${PROXY_PORT:-80}
ENABLE_SSL_PROXY=${ENABLE_SSL_PROXY:-false}
PROXY_SSL_PORT=${PROXY_SSL_PORT:-443}
JAVA_OPTS=${JAVA_OPTS:-''}

JMX_ENABLED=${JMX_ENABLED:-false}
JMX_RMI_HOST=${JMX_RMI_HOST:-127.0.0.1}
JMX_RMI_PORT=${JMX_RMI_PORT:-5000}

JAVA_XMS=${JAVA_XMS:-512M}
JAVA_XMX=${JAVA_XMX:-$JAVA_XMS}

JAVA_OPTS_DEBUG_CHECK='-agentlib:jdwp=transport=dt_socket,server=[yn],suspend=[yn],address=([^:]+:)?(\d+)'
JAVA_OPTS_JMX_CHECK='-Dcom\.sun\.management\.jmxremote(\.(port|authenticate|local\.only|ssl|rmi\.port)=[^\s]+)?'
JAVA_DEBUG_BIND_ALL=${JAVA_DEBUG_BIND_ALL:-false}
JAVA_SECURITY_ENABLED=${JAVA_SECURITY_ENABLED:-true}

JAVA_DNS_TIMEOUT=${JAVA_DNS_TIMEOUT:-60}

MIN_CON_THREADS=${MIN_CON_THREADS:-10}
MAX_CON_THREADS=${MAX_CON_THREADS:-200}

if [ ! -f '/var/lib/tomcat8/.tomcatInitDone' ]
then

   if [[ $JMX_ENABLED == true && ! $JAVA_OPTS =~ $JAVA_OPTS_JMX_CHECK ]]
   then
      JAVA_OPTS="${JAVA_OPTS} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.port=${JMX_RMI_PORT} -Dcom.sun.management.jmxremote.rmi.port=${JMX_RMI_PORT}"
      if [[ ! $JAVA_OPTS =~ '-Djava.rmi.server.hostname=[^\s]+' ]]
      then
         JAVA_OPTS="${JAVA_OPTS} -Djava.rmi.server.hostname=${JMX_RMI_HOST}"
      fi
   fi

   if [[ $DEBUG == true && ! $JAVA_OPTS =~ $JAVA_OPTS_DEBUG_CHECK ]]
   then
      if [[ $JAVA_DEBUG_BIND_ALL == true ]]
      then
         JAVA_OPTS="${JAVA_OPTS} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:${DEBUG_PORT}"
      else
         JAVA_OPTS="${JAVA_OPTS} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=${DEBUG_PORT}"
      fi
   fi

   if [[ ! $JAVA_OPTS =~ '-Xmx\d+[gGmM]' ]]
   then
      JAVA_OPTS="${JAVA_OPTS} -Xmx${JAVA_XMX}"
   fi

   if [[ ! $JAVA_OPTS =~ '-Xms\d+[gGmM]' ]]
   then
      JAVA_OPTS="${JAVA_OPTS} -Xms${JAVA_XMS}"
   fi
   
   if [[ ! $JAVA_OPTS =~ '-XX:\+Use(G1|ConcMarkSweep|Serial|Parallel|ParallelOld|ParNew)GC' ]]
   then
      JAVA_OPTS="${JAVA_OPTS} -XX:+UseG1GC"

      if [[ ! $JAVA_OPTS =~ '-XX:\+ParallelRefProcEnabled' ]]
      then
         JAVA_OPTS="${JAVA_OPTS} -XX:+ParallelRefProcEnabled"
      fi

      if [[ ! $JAVA_OPTS =~ '-XX:\+UseStringDeduplication' ]]
      then
         JAVA_OPTS="${JAVA_OPTS} -XX:+UseStringDeduplication"
      fi
   fi

   if [[ ! $JAVA_OPTS =~ '-Dnetworkaddress\.cache\.ttl=' ]]
   then
      # explicitly limit JVM DNS cache to 60s to cope with re-mapped IPs of other Docker containers the JVM may depend upon
      JAVA_OPTS="${JAVA_OPTS} -Dnetworkaddress.cache.ttl=${JAVA_DNS_TIMEOUT}"
   fi

   if [[ $JAVA_SECURITY_ENABLED == true ]]
   then
      JAVA_SECURITY_ENABLED=yes

      touch /etc/tomcat8/catalina.policy
      chown tomcat8:tomcat8 /etc/tomcat8/catalina.policy

      cat /etc/tomcat8/policy.d/01system.policy >> /etc/tomcat8/catalina.policy
      cat /etc/tomcat8/policy.d/02catalina.policy >> /etc/tomcat8/catalina.policy
      cat /etc/tomcat8/policy.d/03webapps.policy >> /etc/tomcat8/catalina.policy

      # otherwise for will also cut on whitespace
      IFS=$'\n'
      for i in `env`
      do
         key=`echo "$i" | cut -d '=' -f 1`
         value=`echo "$i" | cut -d '=' -f 2-`

         if [[ $key =~ ^JAVA_SECURITY_POLICY_[^_]+_FILE$ && -f "$value" ]]
         then
            echo "Merging in $value into effective Tomcat security policy" > /proc/1/fd/1
            cat $value >> /etc/tomcat8/catalina.policy
         fi
      done
   else
      JAVA_SECURITY_ENABLED=no
   fi

   # need to encode any forward slahes in JAVA_OPTS
   JAVA_OPTS=$(echo "${JAVA_OPTS}" | sed -r "s/(\/)/\\\\\1/g")

   sed -i "s/%JAVA_OPTS%/${JAVA_OPTS}/" /etc/default/tomcat8
   sed -i "s/%JAVA_SECURITY_ENABLED%/${JAVA_SECURITY_ENABLED}/" /etc/default/tomcat8
   sed -i "s/%MIN_CONNECTOR_THREADS%/${MIN_CON_THREADS}/g" /etc/tomcat8/server.xml
   sed -i "s/%MAX_CONNECTOR_THREADS%/${MAX_CON_THREADS}/g" /etc/tomcat8/server.xml

   if [[ $ENABLE_PROXY == true ]]
   then
      sed -i "s/%PROXY_NAME%/${PROXY_NAME}/g" /etc/tomcat8/server.xml
      sed -i "s/%PROXY_PORT%/${PROXY_PORT}/g" /etc/tomcat8/server.xml

      if [[ $ENABLE_SSL_PROXY == true ]]    
      then
         sed -i "s/%PROXY_SSL_PORT%/${PROXY_SSL_PORT}/g" /etc/tomcat8/server.xml
         sed -i "s/<!-- %SSL_PROXY%//g" /etc/tomcat8/server.xml
         sed -i "s/%SSL_PROXY% -->//g" /etc/tomcat8/server.xml
      else
         sed -i 's/[a-zA-Z]*="%PROXY_SSL_[a-zA-Z_]*%"//g' /etc/tomcat8/server.xml
      fi
   else
      sed -i 's/[a-zA-Z]*="%PROXY_[a-zA-Z_]*%"//g' /etc/tomcat8/server.xml
   fi

   echo -e "<?xml version='1.0' encoding='UTF-8'?>\n<tomcat-users>\n</tomcat-users>" > /etc/tomcat8/tomcat-users.xml

   touch /var/lib/tomcat8/.tomcatInitDone
fi