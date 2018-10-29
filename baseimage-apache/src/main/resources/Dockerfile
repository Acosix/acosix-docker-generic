FROM ${docker.from.id}:${docker.from.version.majorVersion}.${docker.from.version.minorVersion}.${docker.from.version.incrementalVersion}

RUN add-apt-repository -y ppa:certbot/ubuntu/certbot \
   && install_clean \
      apache2 \
      certbot \
      python-certbot-apache

RUN openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096

# add prepared files that would be too awkward to handle via RUN / sed
# also include common sample host files for simple pre-selection via an ENV variable
COPY initApache.sh startApache.sh *.conf.sample /tmp/

RUN sed -i 's/SSLCipherSuite HIGH:!aNULL/SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:ECDHE-RSA-AES128-SHA:DHE-RSA-AES128-GCM-SHA256:AES256+EDH:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4/' /etc/apache2/mods-available/ssl.conf \
   && sed -i 's/#SSLHonorCipherOrder on/SSLHonorCipherOrder on/' /etc/apache2/mods-available/ssl.conf \
   && sed -i 's/SSLProtocol all -SSLv3/SSLProtocol all -SSLv3 -TLSv1/' /etc/apache2/mods-available/ssl.conf \
   && sed -i '/<\/IfModule>/i    SSLUseStapling On' /etc/apache2/mods-available/ssl.conf \
   && sed -i '/<\/IfModule>/i    SSLStaplingCache "shmcb:${APACHE_RUN_DIR}/ssl_stapling(32768)"' /etc/apache2/mods-available/ssl.conf \
   && sed -i '/<\/IfModule>/i    SSLOpenSSLConfCmd DHParameters "/etc/ssl/certs/dhparam.pem"' /etc/apache2/mods-available/ssl.conf \
   && rm -f /etc/apache2/sites-available/localhost*.conf* \
   && mkdir -p /etc/my_init.d \
   && mv /tmp/initApache.sh /etc/my_init.d/20_initApache.sh \
   && chmod +x /etc/my_init.d/20_initApache.sh \
   && mkdir /etc/service/apache2 \
   && mv /tmp/startApache.sh /etc/service/apache2/run \
   && mv /tmp/*.host.conf.sample /etc/apache2/sites-available/ \
   && mv /tmp/*.host.*.conf.sample /etc/apache2/sites-available/ \
   && chmod +x /etc/service/apache2/run

RUN a2enmod \
      authz_groupfile \
      proxy \
      proxy_http \
      proxy_html \
      xml2enc \
      expires \
      cache \
      cache_disk \
      rewrite \
      deflate \
      headers \
   && a2disconf \
      serve-cgi-bin \
      other-vhosts-access-log \
   && a2dissite \
      000-default

EXPOSE 80 443

# if derived images don't add /etc/apache2/sites-available/host.conf and /etc/apache2/sites-available/host.ssl.conf
# or don't select a pre-bundled one via ENV, we also expect file mounts to such files
# (as host.conf.sample and host.ssl.conf.sample)
VOLUME ["/srv/apache2/ssl"]

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"