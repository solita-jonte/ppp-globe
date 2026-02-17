FROM mcr.microsoft.com/dotnet/runtime

# Install dependencies for downloading/extracting; adjust to your base image
RUN apt-get update && apt-get install -y curl tar bzip2 && rm -rf /var/lib/apt/lists/*

# Download latest cross-platform sqlcmd (example URL: check GitHub for latest)
RUN curl -L -o /tmp/sqlcmd.tar.bz2 https://github.com/microsoft/go-sqlcmd/releases/download/v1.9.0/sqlcmd-linux-amd64.tar.bz2 && \
    mkdir -p /opt/new-sqlcmd && \
    tar -xjf /tmp/sqlcmd.tar.bz2 -C /opt/new-sqlcmd && \
    rm /tmp/sqlcmd.tar.bz2 && \
    ln -s /opt/new-sqlcmd/sqlcmd /usr/local/bin/sqlcmd

# Copy init script into image
# Path is relative to the build context root (the repo root when used from docker-compose and deploy.sh)
COPY sql_init/*-init*.sql /init/

# Environment variables (must be provided at runtime)
ENV SA_PASSWORD="" \
    CONNECT_DB_NAME="" \
    DB_NAME="" \
    SQL_SERVER_HOST="" \
    SQL_SERVER_USER=""

# Run the init scripts against the target SQL Server.
ENTRYPOINT ["/bin/bash", "-c", \
    "/usr/local/bin/sqlcmd -S \"$SQL_SERVER_HOST\" -d \"$CONNECT_DB_NAME\" -v SQL_DB_NAME=$DB_NAME -U \"$SQL_SERVER_USER\" -P \"$SA_PASSWORD\" -i /init/01-init.sql && \
     /usr/local/bin/sqlcmd -S \"$SQL_SERVER_HOST\" -d \"$DB_NAME\" -U \"$SQL_SERVER_USER\" -P \"$SA_PASSWORD\" -i /init/02-init.sql" \
]
