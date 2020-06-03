#!/bin/bash

set -euo pipefail

DEBUG=${DEBUG:=false}
DEBUG_PORT=${DEBUG_PORT:=8000}

ENABLE_PROXY=${ENABLE_PROXY:=true}
PROXY_NAME=${PROXY_NAME:=localhost}
PROXY_PORT=${PROXY_PORT:=80}
ENABLE_SSL_PROXY=${ENABLE_SSL_PROXY:=false}
PROXY_SSL_PORT=${PROXY_SSL_PORT:=443}
JAVA_OPTS=${JAVA_OPTS:=''}

JMX_ENABLED=${JMX_ENABLED:=false}
JMX_RMI_HOST=${JMX_RMI_HOST:=127.0.0.1}
JMX_RMI_PORT=${JMX_RMI_PORT:=5000}

JAVA_XMS=${JAVA_XMS:=512M}
JAVA_XMX=${JAVA_XMX:-$JAVA_XMS}

JAVA_OPTS_DEBUG_CHECK='-agentlib:jdwp=transport=dt_socket,server=[yn],suspend=[yn],address=([^:]+:)?(\d+)'
JAVA_OPTS_JMX_CHECK='-Dcom\.sun\.management\.jmxremote(\.(port|authenticate|local\.only|ssl|rmi\.port)=[^\s]+)?'
JAVA_DEBUG_BIND_ALL=${JAVA_DEBUG_BIND_ALL:=false}

MIN_CON_THREADS=${MIN_CON_THREADS:=10}
MAX_CON_THREADS=${MAX_CON_THREADS:=200}

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

   # need to encode any forward slahes in JAVA_OPTS
   JAVA_OPTS=$(echo "${JAVA_OPTS}" | sed -r "s/(\/)/\\\\\1/g")

   sed -i "s/%JAVA_OPTS%/${JAVA_OPTS}/" /etc/default/tomcat8
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