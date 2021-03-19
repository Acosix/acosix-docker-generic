FROM ${docker.from.id}:${docker.from.version}

ARG jvmVersion=8

# Headless JDK without src should be the smallest possible
RUN install_clean openjdk-${jvmVersion}-jdk-headless

COPY initCustomJavaCACertificates.sh /etc/my_init.d/00_initCustomJavaCACertificates.sh
RUN chmod +x /etc/my_init.d/00_initCustomCACertificates.sh

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"