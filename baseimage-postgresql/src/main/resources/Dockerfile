FROM ${docker.from.id}:${docker.from.version}

RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
   && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
   && install_clean postgresql-10

COPY initPostgreSQL.sh startPostgreSQL.sh postgresql-logrotate.d /tmp/

RUN mv /tmp/postgresql-logrotate.d /etc/logrotate.d/postgresql \
   && mkdir -p /etc/my_init.d \
   && mv /tmp/initPostgreSQL.sh /etc/my_init.d/20_initPostgreSQL.sh \
   && chmod +x /etc/my_init.d/20_initPostgreSQL.sh \
   && mkdir /etc/service/postgresql \
   && mv /tmp/startPostgreSQL.sh /etc/service/postgresql/run \
   && chmod +x /etc/service/postgresql/run \
   && rm -rf /var/log/postgresql/postgresql-*-main.log

EXPOSE 5432

VOLUME ["/srv/postgresql"]

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"