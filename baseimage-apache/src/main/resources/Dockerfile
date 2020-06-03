FROM ${docker.from.id}:${docker.from.version}

RUN apt-get update \
   && apt-get install -y software-properties-common \
   && add-apt-repository universe \
   && add-apt-repository -y ppa:certbot/certbot \
   && install_clean \
      apache2 \
      certbot \
      python-certbot-apache

RUN openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096

# add prepared files that would be too awkward to handle via RUN / sed
# also include common sample host files for simple pre-selection via an ENV variable
COPY initApache.sh startApache.sh *.conf.sample /tmp/

RUN sed -i 's/SSLCipherSuite HIGH:!aNULL/SSLCipherSuite ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:HIGH:!aNULL:!eNULL:!EXP:!DES:!MD5:!PSK:!RC4/' /etc/apache2/mods-available/ssl.conf \
   && sed -i 's/#SSLHonorCipherOrder on/SSLHonorCipherOrder on/' /etc/apache2/mods-available/ssl.conf \
   && sed -i 's/SSLProtocol all -SSLv3/SSLProtocol ALL -SSLv2 -SSLv3 -TLSv1 -TLSv1.1 +TLSv1.2 +TLSv1.3/' /etc/apache2/mods-available/ssl.conf \
   && sed -i '/<\/IfModule>/i    SSLUseStapling On' /etc/apache2/mods-available/ssl.conf \
   && sed -i '/<\/IfModule>/i    SSLStaplingCache shmcb:${APACHE_RUN_DIR}/ssl_stapling(32768)' /etc/apache2/mods-available/ssl.conf \
   && sed -i '/<\/IfModule>/i    SSLOpenSSLConfCmd DHParameters "/etc/ssl/certs/dhparam.pem"' /etc/apache2/mods-available/ssl.conf \
   && sed -i 's/^LogLevel warn$/LogLevel notice/' /etc/apache2/apache2.conf \
   && sed -i 's/^ServerTokens OS$/ServerTokens Prod/' /etc/apache2/conf-available/security.conf \
   && sed -i 's/^ServerSignature On$/ServerSignature Off/' /etc/apache2/conf-available/security.conf \
   && rm -f /etc/apache2/mods-available/alias.conf \
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
      proxy_ajp \
      proxy_http \
      proxy_http2 \
      proxy_html \
      proxy_hcheck \
      proxy_balancer \
      lbmethod_bybusyness \
      lbmethod_byrequests \
      lbmethod_bytraffic \
      lbmethod_heartbeat \
      expires \
      cache \
      cache_disk \
      rewrite \
      deflate \
      headers \
   && a2dismod -f \
      access_compat \
      auth_basic \
      authn_core \
      authn_file \
      authz_groupfile \
      authz_user \
      autoindex \
      negotiation \
      status \
   && a2disconf \
      localized-error-pages \
      serve-cgi-bin \
      other-vhosts-access-log \
   && a2dissite \
      000-default

EXPOSE 80 443

# we technically support and sort-of expect mounts on
# - /etc/apache2/sites-available/host.conf
# - /etc/apache2/sites-available/host.ssl.conf
# - /srv/apache2/ssl
# ... unless derived images already provide those
# but we don't force those as volumes (anymore)

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"