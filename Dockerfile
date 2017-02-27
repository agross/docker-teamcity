FROM openjdk:8-alpine
MAINTAINER Alexander Groß <agross@therightstuff.de>

EXPOSE 8111

WORKDIR /teamcity

RUN echo Creating teamcity user and group with static ID of 3000 && \
    addgroup -g 3000 -S teamcity && \
    adduser -g "JetBrains TeamCity" -S -h "$(pwd)" -u 3000 -G teamcity teamcity

RUN echo Installing packages && \
    apk add --update coreutils \
                     bash \
                     wget \
                     ca-certificates \
                     openssl

RUN TEAMCITY_VERSION=10.0.4 && \
    \
    DOWNLOAD_URL=https://download.jetbrains.com/teamcity/TeamCity-$TEAMCITY_VERSION.tar.gz && \
    echo Downloading $DOWNLOAD_URL to $(pwd) && \
    wget "$DOWNLOAD_URL" --progress bar:force:noscroll --output-document teamcity.tar.gz && \
    \
    echo Extracting to $(pwd) && \
    tar -xzvf teamcity.tar.gz --directory . && \
    rm -f teamcity.tar.gz && \
    mv TeamCity/* . && \
    rm -rf TeamCity && \
    \
    chown -R teamcity:teamcity .

# Allow TeamCity to retrieve the client IP and host header when running behind a proxy.
# https://confluence.jetbrains.com/display/TCD9/How+To...#HowTo...-Tomcatsettings
RUN sed --in-place --expression 's_</Host>.*$_\
  <Valve className="org.apache.catalina.valves.RemoteIpValve"\n\
               protocolHeader="x-forwarded-proto"\n\
               remoteIpHeader="x-forwarded-for" />\n\
      &_' conf/server.xml

# Check for new versions at: http://tomcat.apache.org/download-native.cgi
RUN echo Compiling the APR based Apache Tomcat Native library && \
    \
    TCNATIVE_VERSION=1.2.12 && \
    BUILD_DIR=/tmp/apr-build && \
    DOWNLOAD_URL=http://www-us.apache.org/dist/tomcat/tomcat-connectors/native/$TCNATIVE_VERSION/source/tomcat-native-$TCNATIVE_VERSION-src.tar.gz && \
    \
    apk add --update apr-util \
                     apr-util-dev \
                     build-base \
                     gcc && \
    \
    mkdir --parents "$BUILD_DIR" && \
    cd "$BUILD_DIR" && \
    \
    wget "$DOWNLOAD_URL" --progress bar:force:noscroll --output-document tomcat-native.tar.gz && \
    tar xzvf tomcat-native.tar.gz && \
    \
    cd "tomcat-native-$TCNATIVE_VERSION-src/native" && \
    ./configure --with-apr="$(which apr-1-config)" --libdir=/usr/java/packages/lib/amd64 && \
    make && \
    make install && \
    \
    rm -rf "$BUILD_DIR" && \
    apk del apr-util-dev \
            build-base \
            gcc

COPY ./docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["teamcity-server", "run"]

USER teamcity
