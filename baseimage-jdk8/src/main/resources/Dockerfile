FROM ${docker.from.id}:${docker.from.version.majorVersion}.${docker.from.version.minorVersion}.${docker.from.version.incrementalVersion}

# Add tools that are commonly used in sub-images
RUN install_clean openjdk-8-jdk-headless

LABEL vendor="${docker.labels.vendor}" \
   ${docker.labels.namespace}.version="${project.version.majorVersion}.${project.version.minorVersion}.${project.version.incrementalVersion}" \
   ${docker.labels.namespace}.is-beta="" \
   ${docker.labels.namespace}.is-production="" \
   ${docker.labels.namespace}.release-date="${docker.labels.release-date}" \
   ${docker.labels.namespace}.maintainer="${docker.labels.maintainer}"