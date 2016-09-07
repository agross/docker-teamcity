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

RUN TEAMCITY_VERSION=10.0.1 && \
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

RUN echo Compiling the APR based Apache Tomcat Native library && \
    \
    BUILD_DIR=/tmp/apr-build && \
    \
    apk add --update apr-util \
                     apr-util-dev \
                     build-base \
                     gcc && \
    \
    mkdir --parents "$BUILD_DIR" && \
    tar xzvf bin/tomcat-native.tar.gz --directory "$BUILD_DIR" && \
    \
    cd "$BUILD_DIR/tomcat-native-1.1.33-src/jni/native" && \
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
