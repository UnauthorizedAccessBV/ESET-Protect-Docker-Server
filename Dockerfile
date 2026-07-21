FROM ubuntu:24.04 AS odbc-build

# Set environment
ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# ODBC Version
ARG ODBC_VERSION=8.0.46

# Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libmysqlclient-dev \
    unixodbc-dev \
    wget \
    cmake \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install MySQL ODBC connector
ADD https://cdn.mysql.com/Downloads/Connector-ODBC/8.0/mysql-connector-odbc-${ODBC_VERSION}-src.tar.gz /tmp/mysql-odbc.tar.gz
RUN mkdir -p /tmp/odbc \
    && tar -xzf /tmp/mysql-odbc.tar.gz -C /tmp/odbc --strip-components=1 \
    && cd /tmp/odbc \
    && cmake . -DDISABLE_GUI=1 -DWITH_UNIXODBC=1 -DMYSQLCLIENT_STATIC_LINKING=TRUE \
    && make

FROM ubuntu:24.04 AS eset-builder

# ESET versions
ARG ESET_VERSION=13.0.450.0

# Add installer and modify it
ADD https://repository.eset.com/v1/com/eset/apps/business/era/server/linux/v13/${ESET_VERSION}/server_linux_x86_64.sh /install/server-linux-x86_64.sh
RUN sed -i 's|config_ProgramConfigDir=.*|config_ProgramConfigDir="/config"|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^config_ProgramDataDir=.*|config_ProgramDataDir="/data"|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^config_ProgramLogsDir=.*|config_ProgramLogsDir="/logs"|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^default_installer_log_file=.*|default_installer_log_file="/logs/EraServerInstaller.log"|g' /install/server-linux-x86_64.sh \
    && chmod +x /install/server-linux-x86_64.sh

# Create user and run installer
RUN groupadd -r eset -g 3537 \
    && useradd --no-log-init -r -g eset -u 3537 eset \
    && /install/server-linux-x86_64.sh \
    --install-type=files \
    --service-user=eset \
    --service-group=eset \
    --skip-license \
    && rm -f /install/server-linux-x86_64.sh

# Final stage
FROM ubuntu:24.04

# Set environment variables
ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Dependencies, taken from: https://help.eset.com/protect_install/latest/en-US/prerequisites_server_linux.html
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    xvfb \
    ca-certificates \
    cifs-utils \
    krb5-user \
    ldap-utils \
    libsasl2-modules-gssapi-mit \
    snmp \
    libodbc2 \
    libodbcinst2 \
    samba \
    python3 \
    lshw \
    && rm -rf /var/lib/apt/lists/*

# Install ODBC
COPY --from=odbc-build /tmp/odbc/lib/libmyodbc8w.so /usr/lib/x86_64-linux-gnu/
COPY --from=odbc-build /tmp/odbc/bin/myodbc-installer /usr/bin/
RUN /usr/bin/myodbc-installer -d -a -n "MySQL ODBC Unicode Driver" -t "DRIVER=/usr/lib/x86_64-linux-gnu/libmyodbc8w.so"

# Create user, directories and symlinks
RUN groupadd -r eset -g 3537 \
    && useradd --no-log-init -r -g eset -u 3537 eset \
    && mkdir -p /etc/opt/eset/RemoteAdministrator \
    && ln -s /config /etc/opt/eset/RemoteAdministrator/Server

# Copy application files from builder stage
COPY --from=eset-builder --chown=eset:eset /opt/eset/RemoteAdministrator/Server /opt/eset/RemoteAdministrator/Server
COPY --from=eset-builder --chown=eset:eset /config /config
COPY --from=eset-builder --chown=eset:eset /data /data
COPY --from=eset-builder --chown=eset:eset /logs /logs

# Volumes
VOLUME [ "/config", "/data", "/logs" ]

# Copy scripts and set permissions
COPY files/ReportPrinterTool /opt/eset/RemoteAdministrator/Server/ReportPrinterTool
COPY files/healthcheck.py /healthcheck.py
COPY files/run.py /run.py
RUN cp /opt/eset/RemoteAdministrator/Server/ReportPrinterTool /opt/eset/RemoteAdministrator/Server/ReportPrinterToolOrig \
    && chmod 755 /opt/eset/RemoteAdministrator/Server/ReportPrinterTool \
    && chmod +x /run.py /healthcheck.py

# Expose ports
EXPOSE 2222 2223

# Healthcheck
HEALTHCHECK --interval=1m --timeout=10s --start-period=10m \
    CMD /healthcheck.py

# Set user
USER eset

# Entrypoint
ENTRYPOINT ["/run.py"]