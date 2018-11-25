FROM ${docker.from.id}:${docker.from.version.majorVersion}.${docker.from.version.minorVersion}.${docker.from.version.incrementalVersion}

# Download and setup GraalVM Community (trimming it down somewhat since it is huuge)
RUN wget -O /tmp/graalvm-ce-${graalvm.version}.tar.gz https://github.com/oracle/graal/releases/download/vm-${graalvm.version}/graalvm-ce-${graalvm.version}-linux-amd64.tar.gz \
   && bsdtar xzf /tmp/graalvm-ce-${graalvm.version}.tar.gz \
   && mkdir -p /usr/lib/jvm  \
   && mv /graalvm-ce-${graalvm.version} /usr/lib/jvm/ \
   && rm /tmp/graalvm-ce-${graalvm.version}.tar.gz \
   && rm /usr/lib/jvm/graalvm-ce-${graalvm.version}/src.zip \
   && rm /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/lib/*.src.zip \
   && rm /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/lib/boot/*.src.zip \
   && rm /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/lib/graalvm/*.src.zip \
   && rm /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/lib/jvmci/*.src.zip \
   && rm /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/lib/truffle/*.src.zip

# TODO Find more ways to strip it down, alternatively build from source with optimisation for size
   
COPY graalvm-ce /tmp/

RUN install_clean \
      equivs \
      gcc \
      zlib1g-dev \
   && equivs-build /tmp/graalvm-ce \
   && dpkg -i /graalvm-ce_${graalvm.version}_all.deb \
   && apt-get autoremove -q -y equivs \
   && rm /graalvm-ce_${graalvm.version}_all.deb \
   && rm /tmp/graalvm-ce

# Only the most commonly used executables are added to the alternatives system
RUN update-alternatives --install /usr/bin/java java /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/java 100 --slave /usr/share/man/man1/java.1.gz java.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/java.1 \
   && update-alternatives --install /usr/bin/jjs jjs /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/jjs 100 --slave /usr/share/man/man1/jjs.1.gz jjs.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/jjs.1 \
   && update-alternatives --install /usr/bin/node node /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/node 100 \
   && update-alternatives --install /usr/bin/npm npm /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/npm 100 \
   && update-alternatives --install /usr/bin/keytool keytool /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/keytool 100 --slave /usr/share/man/man1/keytool.1.gz keytool.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/keytool.1 \
   && update-alternatives --install /usr/bin/rmid rmid /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/rmid 100 --slave /usr/share/man/man1/rmid.1.gz rmid.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/rmid.1 \
   && update-alternatives --install /usr/bin/rmiregistry rmiregistry /usr/lib/jvm/graalvm-ce-${graalvm.version}/jre/bin/rmiregistry 100 --slave /usr/share/man/man1/rmiregistry.1.gz rmiregistry.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/rmiregistry.1 \
   && update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/javac 100 --slave /usr/share/man/man1/javac.1.gz javac.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/javac.1 \
   && update-alternatives --install /usr/bin/javah javah /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/javah 100 --slave /usr/share/man/man1/javah.1.gz javah.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/javah.1 \
   && update-alternatives --install /usr/bin/javap javap /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/javap 100 --slave /usr/share/man/man1/javap.1.gz javap.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/javap.1 \
   && update-alternatives --install /usr/bin/jstack jstack /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/jstack 100 --slave /usr/share/man/man1/jstack.1.gz jstack.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/jstack.1 \
   && update-alternatives --install /usr/bin/jhat jhat /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/jhat 100 --slave /usr/share/man/man1/jhat.1.gz jhat.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/jhat.1 \
   && update-alternatives --install /usr/bin/jmap jmap /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/jmap 100 --slave /usr/share/man/man1/jmap.1.gz jmap.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/jmap.1 \
   && update-alternatives --install /usr/bin/jar jar /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/jar 100 --slave /usr/share/man/man1/jar.1.gz jar.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/jar.1 \
   && update-alternatives --install /usr/bin/javadoc javadoc /usr/lib/jvm/graalvm-ce-${graalvm.version}/bin/javadoc 100 --slave /usr/share/man/man1/javadoc.1.gz javadoc.1.gz /usr/lib/jvm/graalvm-ce-${graalvm.version}/man/man1/javadoc.1

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"