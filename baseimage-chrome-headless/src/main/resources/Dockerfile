FROM ${docker.from.id}:${docker.from.version}

RUN curl -sSL https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
  && echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | tee -a /etc/apt/sources.list.d/google.list \
  && install_clean google-chrome-stable fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-kacst fonts-freefont-ttf libxss1 dbus

COPY startChrome.sh startDBus.sh /tmp/

RUN groupadd -g 12001 chrome \
  && useradd -s /bin/false -d /home/chrome -g chrome -u 12001 -M chrome \
  && mkdir -p /home/chrome/headless /var/cache/chrome /etc/service/chrome /etc/service/dbus /var/run/dbus \
  && chown chrome:chrome /home/chrome /var/cache/chrome \
  && mv /tmp/startChrome.sh /etc/service/chrome/run \
  && mv /tmp/startDBus.sh /etc/service/dbus/run \
  && chmod +x /etc/service/chrome/run /etc/service/dbus/run \
  && sed -i -r 's/(<fork\/>)/<!-- \1 -->/' /usr/share/dbus-1/system.conf

EXPOSE 9222