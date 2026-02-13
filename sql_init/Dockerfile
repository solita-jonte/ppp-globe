FROM mcr.microsoft.com/mssql-tools

# Copy init script into image
# Path is relative to the build context root (the repo root when used from docker-compose and deploy.sh)
COPY sql_init/01-init.sql /init/01-init.sql

# Environment variables (must be provided at runtime)
ENV SA_PASSWORD="" \
    DB_NAME="" \
    SQL_SERVER_HOST="" \
    SQL_SERVER_USER=""

# Run the init script against the target SQL Server.
ENTRYPOINT ["/bin/bash", "-c", "/opt/mssql-tools/bin/sqlcmd -S \"$SQL_SERVER_HOST\" -U \"$SQL_SERVER_USER\" -P \"$SA_PASSWORD\" -d \"$DB_NAME\" -i /init/01-init.sql"]
