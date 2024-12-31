FROM ubuntu:22.04 as odbc-build

# Set environment
ENV LANG=C.UTF-8

# ODBC Version
ARG ODBC_VERSION=8.0.40

# Set non-interactive (for apt etc.)
ENV DEBIAN_FRONTEND noninteractive

# Depdenencies
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

# Use Ubuntu 22.04
FROM ubuntu:22.04

# Set environment
ENV LANG=C.UTF-8

# ESET versions
ARG ESET_VERSION=12.0.273.0

# Set non-interactive (for apt etc.)
ENV DEBIAN_FRONTEND noninteractive

# Set python UNBUFFERED
ENV PYTHONUNBUFFERED 1

# Add qt4 ppa (needed for ubuntu 22.04)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:ubuntuhandbook1/ppa

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
    libodbc2 \
    libodbcinst2 \
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

# Install ODBC
COPY --from=odbc-build /tmp/odbc /tmp/odbc
RUN cp /tmp/odbc/lib/*.so /usr/lib64 \
    && cp /tmp/odbc/bin/* /usr/bin \
    && /usr/bin/myodbc-installer -d -a -n "MySQL ODBC Unicode Driver" -t "DRIVER=/usr/lib64/libmyodbc8w.so" \
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
ADD https://repository.eset.com/v1/com/eset/apps/business/era/server/linux/v12/${ESET_VERSION}/server_linux_x86_64.sh /install/server-linux-x86_64.sh
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