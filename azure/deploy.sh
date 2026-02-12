#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# Load shared config and environment
. "$SCRIPT_DIR/common.sh"
. "$REPO_ROOT/.env"

# Ensure required CLIs and login
ensure_az
ensure_docker

# Ensure required env vars
# Azure SQL does not allow 'sa' as admin login; use a custom admin instead.
SA_USERNAME=pppadmin
: "${SA_PASSWORD:?SA_PASSWORD must be set in .env}"
: "${DB_NAME:?DB_NAME must be set in .env}"
: "${DB_PORT:?DB_PORT must be set in .env}"

RAW_OWNER="${USER:-${USERNAME:-unknown}}"
OWNER_TAG="$(sanitize_ascii "$RAW_OWNER")"
DUEDATE_TAG="$(date -d "30 days" "+%Y-%m-%d")"

# drop any previous log files
find . -maxdepth 1 -name ".deploy-log-*" -delete

# ########################################
# # Resource Group
# ########################################

# echo "Create Resource Group '$RG_NAME' in '$LOCATION'"

# az group create \
#   -n "$RG_NAME" \
#   -l "$LOCATION" \
#   --tags Owner="$OWNER_TAG" DueDate="$DUEDATE_TAG" \
#   -o json > .deploy-log-rg.json

# ########################################
# # Azure SQL Server + Database
# ########################################

# echo "Create Azure SQL Server '$SQL_SERVER_NAME'"

# az sql server create \
#   -g "$RG_NAME" \
#   -n "$SQL_SERVER_NAME" \
#   -l "$LOCATION" \
#   -u "$SA_USERNAME" \
#   -p "$SA_PASSWORD" \
#   -o json > .deploy-log-sql-server.json

# echo "Create Azure SQL Database '$DB_NAME'"

# az sql db create \
#   -g "$RG_NAME" \
#   -s "$SQL_SERVER_NAME" \
#   -n "$DB_NAME" \
#   --service-objective S0 \
#   -o json > .deploy-log-sql-db.json

# wait_for_condition \
#   "SQL DB '$DB_NAME' Online" \
#   "az sql db show -g $RG_NAME -s $SQL_SERVER_NAME -n $DB_NAME --query status -o tsv" \
#   "Online" \
#   900 10

# ########################################
# # Azure Container Registry + Images
# ########################################

# echo "Create Azure Container Registry '$CONTAINER_REGISTRY'"

# az acr create \
#   -g "$RG_NAME" \
#   -n "$CONTAINER_REGISTRY" \
#   --sku Basic \
#   -l "$LOCATION" \
#   -o json > .deploy-log-acr.json

ACR_LOGIN_SERVER=$(az acr show \
  -n "$CONTAINER_REGISTRY" \
  -g "$RG_NAME" \
  --query loginServer -o tsv)

echo "Logging in to ACR '$ACR_LOGIN_SERVER'"
az acr login -n "$CONTAINER_REGISTRY" > .deploy-log-acr-login.json

# Use ACR admin account, so we don't run in role assignment rights in Sandbox
echo "Enable admin usage in ACR"
az acr update -n "$CONTAINER_REGISTRY" --admin-enabled true > .deploy-log-acr-admin.json
ACR_USERNAME=$(az acr credential show -n "$CONTAINER_REGISTRY" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show -n "$CONTAINER_REGISTRY" --query passwords[0].value -o tsv)

########################################
# Tags
########################################

DATALOADER_TAG="${DATALOADER_TAG:-sbx}"
FUNCTIONS_API_TAG="${FUNCTIONS_API_TAG:-sbx}"

# echo "Build and push DataLoader image"
# docker build \
#   -f "$REPO_ROOT/src/DataLoader/Dockerfile" \
#   -t "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" \
#   "$REPO_ROOT" > .deploy-log-dataloader-build.txt
# docker push "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" > .deploy-log-dataloader-push.txt

# echo "Build and push Functions API image"
# docker build \
#   -f "$REPO_ROOT/src/FunctionsApi/Dockerfile" \
#   -t "$ACR_LOGIN_SERVER/functions-api:$FUNCTIONS_API_TAG" \
#   "$REPO_ROOT" > .deploy-log-functions-api-build.txt
# docker push "$ACR_LOGIN_SERVER/functions-api:$FUNCTIONS_API_TAG" > .deploy-log-functions-api-push.txt

# ########################################
# # Container Apps Environment + Jobs
# ########################################

CONTAINERAPPS_ENV_NAME="${CONTAINERAPPS_ENV_NAME:-ppp-globe-ca-env}"

# echo "Create Container Apps environment '$CONTAINERAPPS_ENV_NAME'"

# az containerapp env create \
#   -g "$RG_NAME" \
#   -n "$CONTAINERAPPS_ENV_NAME" \
#   -l "$LOCATION" \
#   -o json > .deploy-log-ca-env.json

# echo "Create DB initializer job (sqlcmd-based, similar to docker-compose)"

# # Read SQL file and collapse newlines to reduce risk of shell parsing issues
# DB_INIT_SQL=$(to_single_line "$REPO_ROOT/sql_db_init/01-init.sql")

# az containerapp job create \
#   --name "ppp-globe-db-init-job" \
#   --resource-group "$RG_NAME" \
#   --environment "$CONTAINERAPPS_ENV_NAME" \
#   --registry-server "$ACR_LOGIN_SERVER" \
#   --registry-username "$ACR_USERNAME" \
#   --registry-password "$ACR_PASSWORD" \
#   --trigger-type Manual \
#   --replica-timeout 600 \
#   --replica-retry-limit 1 \
#   --replica-completion-count 1 \
#   --parallelism 1 \
#   --image "mcr.microsoft.com/mssql-tools" \
#   --cpu 0.25 \
#   --memory 0.5Gi \
#   --env-vars \
#     "SA_PASSWORD=$SA_PASSWORD" \
#   --command '["/opt/mssql-tools/bin/sqlcmd", "-S", "'"$SQL_SERVER_NAME"'.database.windows.net", "-U", "'"$SA_USERNAME"'", "-P", "'"$SA_PASSWORD"'", "-d", "'"$DB_NAME"'", "-Q", "'"$DB_INIT_SQL"'"]' \
#   -o json > .deploy-log-db-init-job.json

# echo "Create DataLoader job"

# az containerapp job create \
#   --name "ppp-globe-dataloader-job" \
#   --resource-group "$RG_NAME" \
#   --environment "$CONTAINERAPPS_ENV_NAME" \
#   --registry-server "$ACR_LOGIN_SERVER" \
#   --registry-username "$ACR_USERNAME" \
#   --registry-password "$ACR_PASSWORD" \
#   --trigger-type Manual \
#   --replica-timeout 1800 \
#   --replica-retry-limit 1 \
#   --replica-completion-count 1 \
#   --parallelism 1 \
#   --image "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" \
#   --cpu 0.5 \
#   --memory 1Gi \
#   --env-vars \
#     "ConnectionStrings__PppDb=Server=$SQL_SERVER_NAME.database.windows.net,$DB_PORT;Database=$DB_NAME;User Id=$SA_USERNAME;Password=$SA_PASSWORD;TrustServerCertificate=True;" \
#   -o json > .deploy-log-dataloader-job.json

# ########################################
# # Run DB initializer and DataLoader
# ########################################

# echo "Run DB initializer job"
# az containerapp job start \
#   --name "ppp-globe-db-init-job" \
#   --resource-group "$RG_NAME" \
#   -o json > .deploy-log-db-init-job-start.json

# echo "Run DataLoader job"
# az containerapp job start \
#   --name "ppp-globe-dataloader-job" \
#   --resource-group "$RG_NAME" \
#   -o json > .deploy-log-dataloader-job-start.json

# ########################################
# # Azure Functions (container-based)
# ########################################

# echo "Create Storage Account '$STORAGE_ACCOUNT_NAME' for Functions"

# az storage account create \
#   -g "$RG_NAME" \
#   -n "$STORAGE_ACCOUNT_NAME" \
#   -l "$LOCATION" \
#   --sku Standard_LRS \
#   -o json > .deploy-log-storage-account.json

# echo "Create Function App '$FUNCTION_APP_NAME'"

# az functionapp create \
#   -g "$RG_NAME" \
#   -n "$FUNCTION_APP_NAME" \
#   --storage-account "$STORAGE_ACCOUNT_NAME" \
#   --consumption-plan-location "$LOCATION" \
#   --functions-version 4 \
#   --os-type Linux \
#   --assign-identity \
#   -o json > .deploy-log-functionapp-create.json

echo "Configure Function App env vars"

# First configure app settings (environment variables)
az functionapp config appsettings set \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --settings \
    "FUNCTIONS_WORKER_RUNTIME=dotnet-isolated" \
    "FUNCTIONS_EXTENSION_VERSION=~4" \
    "ConnectionStrings__PppDb=Server=$SQL_SERVER_NAME.database.windows.net,$DB_PORT;Database=$DB_NAME;User Id=$SA_USERNAME;Password=$SA_PASSWORD;TrustServerCertificate=True;" \
  -o json > .deploy-log-functionapp-appsettings.json

echo "Configure Function App container image"

# Then configure the container image and registry credentials
az functionapp config container set \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --image "$ACR_LOGIN_SERVER/functions-api:$FUNCTIONS_API_TAG" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  -o json > .deploy-log-functionapp-container.json

API_BASE_URL=$(az functionapp show \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --query defaultHostName -o tsv)
API_BASE_URL="https://$API_BASE_URL/api"

########################################
# Static Web App (SWA) deployment
########################################

echo "Prepare frontend config.js with API base URL '$API_BASE_URL'"

cp "$REPO_ROOT/src/Frontend/js/config.template.js" "$REPO_ROOT/src/Frontend/js/config.js"

perl -pi -e "s|__API_BASE_URL__|$API_BASE_URL|g" "$REPO_ROOT/src/Frontend/js/config.js"

echo "Create Static Web App '$SWA_NAME'"

az staticwebapp create \
  -n "$SWA_NAME" \
  -g "$RG_NAME" \
  -l "$LOCATION" \
  --sku Free \
  --source-control "Disabled" \
  -o json > .deploy-log-swa-create.json

echo "Upload Static Web App content from src/Frontend"

az staticwebapp upload \
  -n "$SWA_NAME" \
  -g "$RG_NAME" \
  --source "$REPO_ROOT/src/Frontend" \
  -o json > .deploy-log-swa-upload.json

########################################
# Output frontend URL
########################################

SWA_HOSTNAME=$(az staticwebapp show \
  -n "$SWA_NAME" \
  -g "$RG_NAME" \
  --query "defaultHostname" \
  -o tsv)

FRONTEND_URL="https://$SWA_HOSTNAME"
echo "Deployment complete."
echo "Point your browser towards: $FRONTEND_URL"
echo "Run azure/teardown.sh when done to remove all Azure resources."
