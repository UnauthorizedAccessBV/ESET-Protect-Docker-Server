![Build](https://github.com/UnauthorizedAccessBV/ESET-Protect-Docker-Server/actions/workflows/build.yml/badge.svg)

# ESET PROTECT - Server

This container provides the `Server` component of `ESET PROTECT`. See the [eset-protect-console](https://hub.docker.com/r/esetnederland/eset-protect-console) page for the web console component.

## Quickstart
### Option 1: Manual
First, create a database container:

```shell
docker run --name mysql -e MYSQL_ROOT_PASSWORD=eraadmin -d mysql \
--default-authentication-plugin=mysql_native_password \
--innodb-log-file-size=100M \
--innodb-log-files-in-group=2 \
--max-allowed-packet=30M \
--bind-address=* \
--log_bin_trust_function_creators=1
```

Then, create the server container:
```shell
docker run --name eset-protect-server --link mysql --rm --tty --interactive --publish 2222:2222 --env DB_ADMIN_USERNAME=root --env DB_ADMIN_PASSWORD=eraadmin esetnederland/eset-protect-server
```

Optinally, create a console container:
```shell
docker run --rm --tty --interactive --publish 8080:8080 --link eset-protect-server esetnederland/eset-protect-console
```

### Option 2: docker-compose
Copy the following content to a file called `docker-compose.yml`:
```yaml
version: '3'

services:
    mysql:
        image: mysql:8.0.17
        command: |
            --default-authentication-plugin=mysql_native_password
            --innodb-log-file-size=100M
            --innodb-log-files-in-group=2
            --max-allowed-packet=30M
            --bind-address=*
            --log_bin_trust_function_creators=1
        restart: unless-stopped
        environment:
            - MYSQL_ROOT_USER=root
            - MYSQL_ROOT_PASSWORD=eraadmin
        volumes:
            - mysql:/var/lib/mysql

    eset-protect-server:
        image: esetnederland/eset-protect-server
        depends_on: 
            - mysql
        restart: unless-stopped
        environment:
            - DB_ADMIN_USERNAME=root
            - DB_ADMIN_PASSWORD=eraadmin
        volumes:
            - eset-protect-server-config:/config
            - eset-protect-server-data:/data
            - eset-protect-server-logs:/logs
        ports: 
            - 2222:2222

    eset-protect-console:
        image: esetnederland/eset-protect-console
        depends_on: 
            - eset-protect-server
        restart: unless-stopped
        volumes:
            - eset-protect-console:/config
        ports: 
            - 8080:8080

volumes:
    mysql:
    eset-protect-server-config:
    eset-protect-server-data:
    eset-protect-server-logs:
    eset-protect-console:
```

Then run:
```shell
docker-compose up
```

You should now be able to point your browser to `http://127.0.0.1:8080` and login with `Administrator / eraadmin`.

## Configuration
The following environment variables can be used for configuration:

| Variable                  | 
| ------------------------- | 
| AD_CDN_INCLUDE            |
| AD_SERVER                 |
| AD_USER_NAME              |
| AD_USER_PASSWORD          |
| CERT_AUTH_COMMON_NAME     |
| CERT_AUTH_PASSWORD        |
| CERT_AUTH_PATH            |
| CERT_COUNTRY              |
| CERT_HOSTNAME             |
| CERT_LOCALITY             |
| CERT_ORGANIZATION         |
| CERT_ORGANIZATIONAL_UNIT  |
| CERT_STATE                |
| CERT_VALIDITY             |
| CERT_VALIDITY_UNIT        |
| CONSOLE_PORT              |
| DB_ADMIN_PASSWORD         |
| DB_ADMIN_USERNAME         |
| DB_DRIVER                 |
| DB_HOSTNAME               |
| DB_NAME                   |
| DB_PORT                   |
| DB_TYPE                   |
| DB_USER_PASSWORD          |
| DB_USER_USERNAME          |
| DISABLE_IMP_PROGRAM       |
| ENABLE_IMP_PROGRAM        |
| LICENSE_KEY               |
| LOCALE                    |
| PEER_CERT_PASSWORD        |
| PRODUCT_GUID              |
| SERVER_CERT_PASSWORD      |
| SERVER_CERT_PATH          |
| SERVER_PORT               |
| SERVER_ROOT_PASSWORD      |
| SKIP_CERT                 |

The same settings can also be configured using the following docker secrets:

| Variable                  | 
| ------------------------- | 
| ad-cdn-include            |
| ad-server                 |
| ad-user-name              |
| ad-user-password          |
| cert-auth-common-name     |
| cert-auth-password        |
| cert-auth-path            |
| cert-country              |
| cert-hostname             |
| cert-locality             |
| cert-organization         |
| cert-organizational-unit  |
| cert-state                |
| cert-validity             |
| cert-validity-unit        |
| console-port              |
| db-admin-password         |
| db-admin-username         |
| db-driver                 |
| db-hostname               |
| db-name                   |
| db-port                   |
| db-type                   |
| db-user-password          |
| db-user-username          |
| disable-imp-program       |
| enable-imp-program        |
| license-key               |
| locale                    |
| peer-cert-password        |
| product-guid              |
| server-cert-password      |
| server-cert-path          |
| server-port               |
| server-root-password      |
| skip-cert                 |


## Volumes
This container uses the following volumes:
- /config
- /data
- /logs

## Production deployment
The following compose file deploys the stack using an already existing database and uses Traefik as a reverse proxy:

### .env
```shell
# General settings
HOSTNAME=esetprotect.domain.nl

# Let's Encrypt settings
ACME_EMAIL=user@domain.nl

# Passwords
SERVER_ROOT_PASSWORD=eraadmin
CERT_AUTH_PASSWORD=eraadmin

# Certificate settings
CERT_AUTH_COMMON_NAME=ESET Protect Server Certification Authority
CERT_COUNTRY=NL
CERT_LOCALITY=Sliedrecht
CERT_ORGANIZATION=ESET Nederland
CERT_ORGANIZATIONAL_UNIT=IT
CERT_STATE=ZH

# Database settings
DB_HOSTNAME=db.domain.nl
DB_PORT=3306
DB_NAME=era_db
DB_USER_USERNAME=era_db_user
DB_USER_PASSWORD=eraadmin

# Console settings
HSTS_ENABLE=true
REMOTE_ADDRESS_SOURCE=x-forwarded-for-last
```

### docker-compose.yml
```yaml
version: '3'

services:
    traefik:
        image: traefik:2.2
        restart: unless-stopped
        command:
            #- --api.insecure=true # Uncomment to enable dashboard on port 8080
            - --providers.docker=true
            - --providers.docker.exposedbydefault=false
            - --entrypoints.http.address=:80
            - --entrypoints.https.address=:443
            - --entrypoints.em-agent.address=:2222
            - --certificatesResolvers.le.acme.email=${ACME_EMAIL}
            - --certificatesResolvers.le.acme.httpChallenge.entryPoint=http
            - --certificatesResolvers.le.acme.storage=/etc/traefik/acme.json
            #- --providers.file.directory=/etc/traefik/dynamic # Uncomment to use Dynamic configurations
        ports:
            - 80:80
            - 443:443
            - 2222:2222
            - 8080:8080
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - traefik:/etc/traefik

    eset-protect-server:
        image: esetnederland/eset-protect-server:latest
        restart: unless-stopped
        environment:
            - CERT_AUTH_COMMON_NAME=${CERT_AUTH_COMMON_NAME}
            - CERT_AUTH_PASSWORD=${CERT_AUTH_PASSWORD}
            - CERT_COUNTRY=${CERT_COUNTRY}
            - CERT_HOSTNAME=${HOSTNAME}
            - CERT_LOCALITY=${CERT_LOCALITY}
            - CERT_ORGANIZATION=${CERT_ORGANIZATION}
            - CERT_ORGANIZATIONAL_UNIT=${CERT_ORGANIZATIONAL_UNIT}
            - CERT_STATE=${CERT_STATE}
            - DB_HOSTNAME=${DB_HOSTNAME}
            - DB_PORT=${DB_PORT}
            - DB_NAME=${DB_NAME}
            - DB_USER_USERNAME=${DB_USER_USERNAME}
            - DB_USER_PASSWORD=${DB_USER_PASSWORD}
            - SERVER_ROOT_PASSWORD=${SERVER_ROOT_PASSWORD}
        volumes:
            - eset-protect-server-config:/config
            - eset-protect-server-data:/data
            - eset-protect-server-logs:/logs
        labels:
            - traefik.enable=true
            - traefik.tcp.routers.em-agent.rule=HostSNI(`*`)
            - traefik.tcp.routers.em-agent.entrypoints=em-agent
            - traefik.tcp.routers.em-agent.service=em-agent
            - traefik.tcp.routers.em-agent.tls=true
            - traefik.tcp.routers.em-agent.tls.passthrough=true
            - traefik.tcp.services.em-agent.loadbalancer.server.port=2222

    eset-protect-console:
        image: esetnederland/eset-protect-console:latest
        restart: unless-stopped
        environment:
            - HSTS_ENABLE=${HSTS_ENABLE}
            - REMOTE_ADDRESS_SOURCE=${REMOTE_ADDRESS_SOURCE}
        volumes:
            - eset-protect-console:/config
        labels:
            - traefik.enable=true
            - traefik.http.routers.eset-protect-console.rule=Host(`${HOSTNAME}`)
            - traefik.http.routers.eset-protect-console.entrypoints=http
            - traefik.http.routers.eset-protect-console.middlewares=eset-protect-console-redirect
            - traefik.http.routers.eset-protect-console-secure.rule=Host(`${HOSTNAME}`)
            - traefik.http.routers.eset-protect-console-secure.entrypoints=https
            - traefik.http.routers.eset-protect-console-secure.tls=true
            - traefik.http.routers.eset-protect-console-secure.tls.certresolver=le
            # - traefik.http.routers.eset-protect-console-secure.tls.options=intermediate@file # Uncomment to use internediate SSL configuration. Needs a dynamic configuration file
            - traefik.http.routers.eset-protect-console-secure.middlewares=eset-protect-console-secure-headers,eset-protect-console-secure-redirect
            - traefik.http.middlewares.eset-protect-console-redirect.redirectscheme.scheme=https
            - traefik.http.middlewares.eset-protect-console-secure-headers.headers.customFrameOptionsValue=SAMEORIGIN
            - traefik.http.middlewares.eset-protect-console-secure-headers.headers.sslredirect=true
            - traefik.http.middlewares.eset-protect-console-secure-headers.headers.stsSeconds=63072000
            - traefik.http.middlewares.eset-protect-console-secure-redirect.redirectregex.regex=^(https:\/\/[^:\/]+(:\\d+)?)\/$$
            - traefik.http.middlewares.eset-protect-console-secure-redirect.redirectregex.replacement=$${1}/era/webconsole/
            - traefik.http.middlewares.eset-protect-console-secure-redirect.redirectregex.permanent=true

volumes:
    traefik:
    eset-protect-server-config:
    eset-protect-server-data:
    eset-protect-server-logs:
    eset-protect-console:
```

If you want an A+ grade on the Qualys SSL Server test uncomment the `dynamic configuration` and `intermediate ssl` lines in the above config, and write the following content to `/etc/traefik/dynamic/ssl.toml` (or directly to its volume):

```toml
[tls.options]
  [tls.options.modern]
    minVersion = "VersionTLS13"

  [tls.options.intermediate]
    minVersion = "VersionTLS12"
    cipherSuites = [
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
    ]

  [tls.options.default]
    minVersion = "VersionTLS12"
```