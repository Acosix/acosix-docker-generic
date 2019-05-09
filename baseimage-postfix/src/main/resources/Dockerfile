FROM ${docker.from.id}:${docker.from.version}

# need to set a dummy mailname now (must be overriden via initPostfix.sh + env variables) so unattended install works
RUN echo "postfix postfix/mailname string example.com" | debconf-set-selections \
   && echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections \
   && install_clean postfix \
   && groupadd -g 11000 vmail \
   && useradd -s /bin/false -g vmail -u 11000 vmail \
   && echo "root: root" >> /etc/aliases \
   && newaliases

COPY initPostfix.sh postfix-ng.conf /tmp/
RUN mkdir -p /etc/my_init.d \
   && mv /tmp/postfix-ng.conf /etc/syslog-ng/conf.d/postfix-ng.conf \
   && mv /tmp/initPostfix.sh /etc/my_init.d/20_initPostfix.sh \
   && chmod +x /etc/my_init.d/20_initPostfix.sh

EXPOSE 25

# VOLUME ["/srv/apache2/ssl"]

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"