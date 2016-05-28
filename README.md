# docker-teamcity

[![](https://imagelayers.io/badge/agross/teamcity:latest.svg)](https://imagelayers.io/?images=agross/teamcity:latest 'Get your own badge on imagelayers.io')

This Dockerfile allows you to build images to deploy your own [TeamCity](http://www.jetbrains.com/teamcity/) instance. It has been tested on [Fedora 23](https://getfedora.org/) and [CentOS 7](https://www.centos.org/).

*Please remember to back up your data directories often, especially before upgrading to a newer version.*

## Test it

1. [Install docker.](http://docs.docker.io/en/latest/installation/)
2. Run the container. (Stop with CTRL-C.)

  ```sh
  docker run -it -p 8111:8111 agross/teamcity
  ```

3. Open your browser and navigate to `http://localhost:8111`.

## Run it as service on systemd

1. Decide where to put TeamCity data and logs. Set domain name/server name and the public port.

  ```sh
  TEAMCITY_DATA="/var/data/teamcity"
  TEAMCITY_LOGS="/var/log/teamcity"

  DOMAIN=example.com
  PORT=8011
  ```

2. Create directories to store data and logs outside of the container.

  ```sh
  mkdir --parents "$TEAMCITY_DATA" \
                  "$TEAMCITY_LOGS"
  ```

3. Set permissions.

  The Dockerfile creates a `teamcity` user and group. This user has a `UID` and `GID` of `3000`. Make sure to add a user to your host system with this `UID` and `GID` and allow this user to read and write to `$TEAMCITY_DATA` and `$TEAMCITY_LOGS`. The name of the host user and group in not important.

  ```sh
  # Create teamcity group and user in docker host, e.g.:
  groupadd --gid 3000 --system teamcity
  useradd --uid 3000 --gid 3000 --system --shell /sbin/nologin --comment "JetBrains TeamCity" teamcity

  # 3000 is the ID of the teamcity user and group created by the Dockerfile.
  chown -R 3000:3000 "$TEAMCITY_DATA" "$TEAMCITY_LOGS"
  ```

4. Create your container.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  Use `--env` to specify JVM and TeamCity server options, e.g. for [memory](https://confluence.jetbrains.com/display/TCD9/Installing+and+Configuring+the+TeamCity+Server#InstallingandConfiguringtheTeamCityServer-memory).

  ```sh
  docker create -it --env TEAMCITY_SERVER_MEM_OPTS='-Xms1g -Xmx3g' \
                    -p $PORT:8111 \
                    -v "$TEAMCITY_DATA:/teamcity/.BuildServer:z" \
                    -v "$TEAMCITY_LOGS:/teamcity/logs:z" \
                    --name teamcity \
                    agross/teamcity
  ```

5. Create systemd unit, e.g. `/etc/systemd/system/teamcity-server.service`.

  ```sh
  cat <<EOF > "/etc/systemd/system/teamcity-server.service"
  [Unit]
  Description=JetBrains TeamCity Server
  Requires=docker.service
  After=docker.service

  [Service]
  Restart=always
  # When docker stop is executed, the docker-entrypoint.sh trap + wait combination
  # will generate an exit status of 143 = 128 + 15 (SIGTERM).
  # More information: http://veithen.github.io/2014/11/16/sigterm-propagation.html
  SuccessExitStatus=143
  PrivateTmp=true
  ExecStart=/usr/bin/docker start --attach=true teamcity
  ExecStop=/usr/bin/docker stop --time=60 teamcity

  [Install]
  WantedBy=multi-user.target
  EOF

  systemctl enable teamcity-server.service
  systemctl start teamcity-server.service
  ```

6. Setup logrotate, e.g. `/etc/logrotate.d/teamcity`.

  ```sh
  cat <<EOF > "/etc/logrotate.d/teamcity-server"
  $TEAMCITY_LOGS/*.log
  {
    rotate 7
    daily
    dateext
    missingok
    notifempty
    sharedscripts
    copytruncate
    compress
  }
  EOF
  ```
7. Add nginx configuration, e.g. `/etc/nginx/conf.d/teamcity.conf`.

  ```sh
  cat <<EOF > "/etc/nginx/conf.d/teamcity.conf"
  upstream teamcity {
    server localhost:$PORT;
  }

  map $http_upgrade $connection_upgrade {
      default upgrade;
      ''      '';
  }

  server {
    listen           80;
    listen      [::]:80;

    server_name $DOMAIN;

    access_log  /var/log/nginx/$DOMAIN.access.log;
    error_log   /var/log/nginx/$DOMAIN.error.log;

    # Do not limit upload.
    client_max_body_size 0;

    # Required to avoid HTTP 411: see issue #1486 (https://gitteamcity.com/dotcloud/docker/issues/1486)
    chunked_transfer_encoding on;

    location / {
      proxy_pass http://teamcity;

      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Host \$http_host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_http_version 1.1;

      # Support WebSockets.
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
    }
  }
  EOF

  nginx -s reload
  ```

  Make sure SELinux policy allows nginx to access port `$PORT` (the first part of `-p $PORT:8080` of step 3).

  ```sh
  if [ $(semanage port --list | grep --count "^http_port_t.*$PORT") -eq 0 ]; then
    if semanage port --add --type http_port_t --proto tcp $PORT; then
      echo Added port $PORT as a valid port for nginx:
      semanage port --list | grep ^http_port_t
    else
      >&2 echo Could not add port $PORT as a valid port for nginx. Please add it yourself. More information: http://axilleas.me/en/blog/2013/selinux-policy-for-nginx-and-gitlab-unix-socket-in-fedora-19/
    fi
  else
    echo Port $PORT is already a valid port for nginx:
    semanage port --list | grep ^http_port_t
  fi
  ```

8. Configure TeamCity.

  Follow the steps of the installation [instructions for JetBrains TeamCity](https://confluence.jetbrains.com/display/TCD9/Installing+and+Configuring+the+TeamCity+Server#InstallingandConfiguringtheTeamCityServer-ConfiguringTeamCityServer) using paths inside the docker container located under

    * `/teamcity/.BuildServer`.

9. Update to a newer version.

  ```sh
  docker pull agross/teamcity

  systemctl stop teamcity.service

  # Back up $TEAMCITY_DATA.
  tar -zcvf "teamcity-data-$(date +%F-%H-%M-%S).tar.gz" "$TEAMCITY_DATA"

  docker rm teamcity

  # Repeat step 4 and create a new image.
  docker create ...

  systemctl start teamcity-server.service
  ```

10. Trust self-signed SSL certificates.

  If you need to connect to e.g. an LDAP server that uses a self-signed certificate or use the NuGet trigger with a NuGet feed served with a self-signed certificate you need to add those certificates to the JVM trust store inside the container.

  With the docker container running, execute:

  ```sh
  HOST=ldap.example.com:636

  docker exec -it -u root teamcity bash -c " \
    echo -n | openssl s_client -connect $HOST | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > /tmp/$HOST && \
    \$JAVA_HOME/bin/keytool -import -alias $HOST -file /tmp/$HOST -keystore "\$JAVA_HOME/jre/lib/security/cacerts" -noprompt -storepass changeit && \
    rm /tmp/$HOST"
  ```

## Building and testing the `Dockerfile`

1. Build the `Dockerfile`.

  ```sh
  docker build --tag agross/teamcity:testing .

  docker images
  # Should contain:
  # REPOSITORY                        TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
  # agross/teamcity                   testing             0dcb8bf6093f        49 seconds ago      405.4 MB

  ```

2. Prepare directories for testing.

  ```sh
  TEST_DIR="/tmp/teamcity-testing"

  mkdir --parents "$TEST_DIR/data" \
                  "$TEST_DIR/logs"
  chown -R 3000:3000 "$TEST_DIR"
  ```

3. Run the container built in step 1.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker run -it --rm \
                 --name teamcity-testing \
                 -p 8111:8111 \
                 -v "$TEST_DIR/data:/teamcity/.BuildServer:z" \
                 -v "$TEST_DIR/logs:/teamcity/logs:z" \
                 agross/teamcity:testing
  ```

4. Open a shell to your running container.

  ```sh
  docker exec -it teamcity-testing bash
  ```

5. Run bash instead of starting TeamCity.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker run -it --rm \
                 --name teamcity-testing \
                 -p 8111:8111 \
                 -v "$TEST_DIR/data:/teamcity/.BuildServer:z" \
                 -v "$TEST_DIR/logs:/teamcity/logs:z" \
                 agross/teamcity:testing \
                 bash
  ```
