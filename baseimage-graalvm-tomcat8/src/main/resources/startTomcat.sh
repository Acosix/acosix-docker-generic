#!/bin/sh

# Based on tomcat8 startup script from the APT tomcat8 package
# Since baseimage my_init system requires a non-forking script
# for our tomcat daemon this adapted script uses run instead
# of start, and does away with some of the flexibility of an
# init.d script

set -e

PATH=/bin:/usr/bin:/sbin:/usr/sbin
DESC="Tomcat servlet engine"
DEFAULT=/etc/default/tomcat8
JVM_TMP=/tmp/tomcat8-tomcat8-tmp

if [ `id -u` -ne 0 ]; then
        echo "You need root privileges to run this script"
        exit 1
fi

# Make sure tomcat is started with system locale
if [ -r /etc/default/locale ]; then
        . /etc/default/locale
        export LANG
fi

. /lib/lsb/init-functions

if [ -r /etc/default/rcS ]; then
        . /etc/default/rcS
fi


# The following variables can be overwritten in $DEFAULT

# Run Tomcat 7 as this user ID and group ID
tomcat8_USER=tomcat8
tomcat8_GROUP=tomcat8

find_jdks()
{
    # Try to derive preferred JDK_DIR from configured alternatives
    JAVA_PATH=`readlink /etc/alternatives/java 2>/dev/null`
    if [ -f "${JAVA_PATH}" ]
    then
        JDK_DIRS=$(echo "${JAVA_PATH}" | sed -r "s/\/(jre\/)?bin\/java$//")
    fi
    
    # Use default-java for first lookup after configured alternatives 
    JDK_DIRS="${JDK_DIRS} /usr/lib/jvm/default-java"

    # Add common JDKs in decreasing priority based on version
    for java_version in 11 10 9 8 7 6
    do
        for jvmdir in /usr/lib/jvm/java-${java_version}-openjdk* \
                      /usr/lib/jvm/jdk-${java_version}-oracle-* \
                      /usr/lib/jvm/jre-${java_version}-oracle-* \
                      /usr/lib/jvm/java-${java_version}-oracle* \
                      /usr/lib/jvm/java-${java_version}-sun* 
        do
            if [ -d "${jvmdir}" -a "${jvmdir}" != "/usr/lib/jvm/java-${java_version}-openjdk-common" ]
            then
                JDK_DIRS="${JDK_DIRS} ${jvmdir}"
            fi
        done
    done
    
    # Look for alternative JDKs / JVMs (only Graal VM for now)
    for jvmdir in /usr/lib/jvm/graalvm-*
    do
        if [ -d "${jvmdir}" ]
        then
            JDK_DIRS="${JDK_DIRS} ${jvmdir}"
        fi
    done
}

# The first existing directory is used for JAVA_HOME (if JAVA_HOME is not
# defined in $DEFAULT)
JDK_DIRS=""
find_jdks

# Look for the right JVM to use
for jdir in $JDK_DIRS; do
    if [ -r "$jdir/bin/java" -a -z "${JAVA_HOME}" ]; then
        JAVA_HOME="$jdir"
    fi
done
export JAVA_HOME

# Directory where the Tomcat 7binary distribution resides
CATALINA_HOME=/usr/share/tomcat8

# Directory for per-instance configuration files and webapps
CATALINA_BASE=/var/lib/tomcat8

# Use the Java security manager? (yes/no)
tomcat8_SECURITY=no

# Default Java options
# Set java.awt.headless=true if JAVA_OPTS is not set so the
# Xalan XSL transformer can work without X11 display on JDK 1.4+
# It also looks like the default heap size of 64M is not enough for most cases
# so the maximum heap size is set to 128M
if [ -z "$JAVA_OPTS" ]; then
        JAVA_OPTS="-Djava.awt.headless=true -Xmx128M"
fi

# End of variables that can be overwritten in $DEFAULT

# overwrite settings from default file
if [ -f "$DEFAULT" ]; then
        . "$DEFAULT"
fi

if [ ! -f "$CATALINA_HOME/bin/bootstrap.jar" ]; then
        log_failure_msg "tomcat8 is not installed"
        exit 1
fi

POLICY_CACHE="$CATALINA_BASE/work/catalina.policy"

if [ -z "$CATALINA_TMPDIR" ]; then
        CATALINA_TMPDIR="$JVM_TMP"
fi

# Set the JSP compiler if set in the tomcat8.default file
if [ -n "$JSP_COMPILER" ]; then
        JAVA_OPTS="$JAVA_OPTS -Dbuild.compiler=\"$JSP_COMPILER\""
fi

SECURITY=""
if [ "$tomcat8_SECURITY" = "yes" ]; then
        SECURITY="-security"
fi

# Define other required variables
CATALINA_SH="$CATALINA_HOME/bin/catalina.sh"

# Look for Java Secure Sockets Extension (JSSE) JARs
if [ -z "${JSSE_HOME}" -a -r "${JAVA_HOME}/jre/lib/jsse.jar" ]; then
    JSSE_HOME="${JAVA_HOME}/jre/"
fi

if [ -z "$JAVA_HOME" ]; then
      log_failure_msg "no JDK or JRE found - please set JAVA_HOME"
      exit 1
fi

if [ ! -d "$CATALINA_BASE/conf" ]; then
      log_failure_msg "invalid CATALINA_BASE: $CATALINA_BASE"
      exit 1
fi

# Regenerate POLICY_CACHE file
umask 022
echo "// AUTO-GENERATED FILE from /etc/tomcat8/policy.d/" > "$POLICY_CACHE"
echo ""  >> "$POLICY_CACHE"
cat $CATALINA_BASE/conf/policy.d/*.policy >> "$POLICY_CACHE"

# Remove / recreate JVM_TMP directory
rm -rf "$JVM_TMP"
mkdir -p "$JVM_TMP" || {
      log_failure_msg "could not create JVM temporary directory"
      exit 1
}
chown $tomcat8_USER:$tomcat8_GROUP "$JVM_TMP"

touch $CATALINA_BASE/logs/catalina.out
chown $tomcat8_USER:$tomcat8_GROUP $CATALINA_BASE/logs/catalina.out

set -a

JAVA_HOME="${JAVA_HOME}"
CATALINA_HOME="${CATALINA_HOME}"
CATALINA_BASE="${CATALINA_BASE}"
JAVA_OPTS="${JAVA_OPTS}"
CATALINA_TMPDIR="${CATALINA_TMPDIR}"
LANG="${LANG}"
JSSE_HOME="${JSSE_HOME}"

cd $CATALINA_BASE
exec /sbin/setuser $tomcat8_USER $CATALINA_SH run $SECURITY >> $CATALINA_BASE/logs/catalina.out 2>&1