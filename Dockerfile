FROM openjdk:8-alpine
LABEL maintainer "Alexander Groß <agross@therightstuff.de>"

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["teamcity-server", "run"]

EXPOSE 8111

WORKDIR /teamcity

HEALTHCHECK --start-period=2m \
            CMD wget --server-response --output-document=/dev/null http://localhost:8111/login.html || exit 1

ARG VERSION=2021.1
ARG DOWNLOAD_URL=https://download.jetbrains.com/teamcity/TeamCity-$VERSION.tar.gz
ARG SHA_DOWNLOAD_URL=https://download.jetbrains.com/teamcity/TeamCity-$VERSION.tar.gz.sha256

RUN echo Creating teamcity user and group with static ID of 3000 && \
    addgroup -g 3000 -S teamcity && \
    adduser -g "JetBrains TeamCity" -S -h "$(pwd)" -u 3000 -G teamcity teamcity && \
    \
    echo Installing packages && \
    apk add --no-cache bash \
                       coreutils \
                       ca-certificates \
                       git \
                       libressl \
                       tomcat-native \
                       wget && \
    \
    echo Downloading $DOWNLOAD_URL to $(pwd) && \
    wget --progress bar:force:noscroll \
         "$DOWNLOAD_URL" && \
    \
    echo Verifying download && \
    wget --progress bar:force:noscroll \
         --output-document \
         download.sha256 \
         "$SHA_DOWNLOAD_URL" && \
    \
    sha256sum -c download.sha256 && \
    rm download.sha256 && \
    \
    echo Extracting to $(pwd) && \
    tar -xzvf TeamCity-$VERSION.tar.gz --directory . && \
    rm TeamCity-$VERSION.tar.gz && \
    mv TeamCity/* . && \
    rm -r TeamCity && \
    \
    chown -R teamcity:teamcity . && \
    chmod +x /docker-entrypoint.sh

# Allow TeamCity to retrieve the client IP and host header when running behind a proxy.
# https://confluence.jetbrains.com/display/TCD9/How+To...#HowTo...-Tomcatsettings
RUN sed --in-place --expression 's_</Host>.*$_\
  <Valve className="org.apache.catalina.valves.RemoteIpValve"\n\
               protocolHeader="x-forwarded-proto"\n\
               remoteIpHeader="x-forwarded-for" />\n\
      &_' conf/server.xml

USER teamcity
