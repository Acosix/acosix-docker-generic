FROM phusion/baseimage:${phusion.baseimage.version}

# Add tools that are commonly used in sub-images
RUN apt-get update \
  && apt-get dist-upgrade -y \
  && install_clean \
      inetutils-ping \
      dnsutils \
      wget \
      zip \
      unzip \
      bsdtar \
      lsof \
      libnss3-tools \
  && apt-get autoremove -y

COPY initCustomCACertificates.sh /etc/my_init.d/00_initCustomCACertificates.sh
RUN chmod +x /etc/my_init.d/00_initCustomCACertificates.sh

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"