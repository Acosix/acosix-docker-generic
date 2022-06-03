FROM ${docker.from.id}:${docker.from.version}

RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
   && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
   && install_clean \
      postgresql-14 \
      jq

COPY initPostgreSQL.sh startPostgreSQL.sh postgresql-logrotate.d postgresql.pam pam-oidc.sh /tmp/

RUN mv /tmp/postgresql-logrotate.d /etc/logrotate.d/postgresql \
   && mkdir -p /etc/my_init.d \
   && mv /tmp/initPostgreSQL.sh /etc/my_init.d/20_initPostgreSQL.sh \
   && chmod +x /etc/my_init.d/20_initPostgreSQL.sh \
   && mkdir /etc/service/postgresql \
   && mv /tmp/startPostgreSQL.sh /etc/service/postgresql/run \
   && chmod +x /etc/service/postgresql/run \
   && mv /tmp/postgresql.pam /etc/pam.d/postgresql \
   && mv /tmp/pam-oidc.sh /usr/lib/ \
   && chmod +x /usr/lib/pam-oidc.sh \
   && rm -rf /var/log/postgresql/postgresql-*-main.log

EXPOSE 5432

VOLUME ["/srv/postgresql"]

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"