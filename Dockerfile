# Use Ubuntu 18.04
FROM ubuntu:20.04

# Versions
ARG ESET_VERSION=9.1.2301.0
ARG ODBC_VERSION=8.0.17

# Set non-interactive (for apt etc.)
ENV DEBIAN_FRONTEND noninteractive

# Set python UNBUFFERED
ENV PYTHONUNBUFFERED 1

# Add qt4 ppa (needed for ubuntu 20.04)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository ppa:rock-core/qt4

# Dependencies, taken from: https://help.eset.com/protect_install/latest/en-US/prerequisites_server_linux.html 
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    ca-certificates \
    cifs-utils \
    libqtwebkit4 \
    krb5-user \
    ldap-utils \
    libsasl2-modules-gssapi-mit \
    snmp \
    libodbc1 \
    odbcinst1debian2 \
    libssl-dev \
    samba \
    python3 \
    lshw \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir \
    /install \
    /config \
    /data \
    /logs

# Install MySQL ODBC connector
ADD https://downloads.mysql.com/archives/get/p/10/file/mysql-connector-odbc-${ODBC_VERSION}-linux-ubuntu19.04-x86-64bit.tar.gz /install/mysql-odbc.tar.gz
RUN mkdir -p /tmp/odbc \
    && tar -xzf /install/mysql-odbc.tar.gz -C /tmp/odbc --strip-components=1 \
    && cp /tmp/odbc/lib/*.so /usr/lib64 \
    && /tmp/odbc/bin/myodbc-installer -d -a -n "MySQL ODBC Unicode Driver" \ 
    -t "DRIVER=/usr/lib64/libmyodbc8w.so;SETUP=/usr/lib64/myodbc8S.so" \
    && rm -rf /tmp/odbc \
    && rm -f /install/mysql-odbc.tar.gz

# Create user
RUN groupadd -r eset -g 3537 \
    &&  useradd --no-log-init -r -g eset -u 3537 eset

# Create directories and synlinks
RUN mkdir -p \
    /etc/opt/eset/RemoteAdministrator \
    /var/opt/eset/RemoteAdministrator \
    /var/log/eset \
    && ln -s /config /etc/opt/eset/RemoteAdministrator/Server \
    && ln -s /data /var/opt/eset/RemoteAdministrator/Server \
    && ln -s /logs /var/log/eset/RemoteAdministrator

# Add installer
ADD https://repository.eset.com/v1/com/eset/apps/business/era/server/linux/v9/${ESET_VERSION}/server_linux_x86_64.sh /install/server-linux-x86_64.sh
RUN sed -i 's|config_ProgramConfigDir=.*|config_ProgramConfigDir=/config|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^config_ProgramDataDir=.*|config_ProgramDataDir=/data|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^config_ProgramLogsDir=.*|config_ProgramLogsDir=/logs|g' /install/server-linux-x86_64.sh \
    && chmod +x /install/server-linux-x86_64.sh

# Run installer in "files" mode
RUN install/server-linux-x86_64.sh \
    --install-type=files \
    --service-user=eset \
    --service-group=eset \
    --skip-license \
    && rm -f /install/server-linux-x86_64.sh

# Fix permissions
RUN chown -R eset:eset \
    /opt/eset/RemoteAdministrator/Server/setup

# Volumes
VOLUME [ "/config", "/data", "/logs" ]

# Add entrypoint and healthcheck
COPY files/healthcheck.py /healthcheck.py
COPY files/run.py /run.py
RUN chmod +x \ 
    /run.py \
    /healthcheck.py

# Create script for report generation
RUN cp /opt/eset/RemoteAdministrator/Server/ReportPrinterTool /opt/eset/RemoteAdministrator/Server/ReportPrinterToolOrig
COPY files/ReportPrinterTool /opt/eset/RemoteAdministrator/Server/ReportPrinterTool
RUN chmod 755 /opt/eset/RemoteAdministrator/Server/ReportPrinterTool

# Ports
EXPOSE 2222 2223

# Healthcheck
HEALTHCHECK --interval=1m --timeout=10s --start-period=10m \  
    CMD /healthcheck.py

# Set user
USER eset

# Entrypoint
ENTRYPOINT ["/run.py"]