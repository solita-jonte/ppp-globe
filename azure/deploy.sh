#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# Load shared config and environment
. "$SCRIPT_DIR/common.sh"
. "$REPO_ROOT/.env"

# Ensure required CLIs and login
ensure_az_and_swa

# Ensure required env vars
SA_USERNAME=sa
: "${SA_PASSWORD:?SA_PASSWORD must be set in .env}"
: "${DB_NAME:?DB_NAME must be set in .env}"
: "${DB_PORT:?DB_PORT must be set in .env}"

RAW_OWNER="${USER:-${USERNAME:-unknown}}"
OWNER_TAG="$(sanitize_ascii "$RAW_OWNER")"
DUEDATE_TAG="$(date -d "30 days" "+%Y-%m-%d")"

########################################
# Resource Group
########################################

echo "Create Resource Group '$RG_NAME' in '$LOCATION'"

az group create \
  -n "$RG_NAME" \
  -l "$LOCATION" \
  --tags Owner="$OWNER_TAG" DueDate="$DUEDATE_TAG" \
  -o json > .deploy-rg.json

########################################
# Azure SQL Server + Database
########################################

echo "Create Azure SQL Server '$SQL_SERVER_NAME'"

az sql server create \
  -g "$RG_NAME" \
  -n "$SQL_SERVER_NAME" \
  -l "$LOCATION" \
  -u "$SA_USERNAME" \
  -p "$SA_PASSWORD" \
  -o json > .deploy-sql-server.json

echo "Create Azure SQL Database '$DB_NAME'"

az sql db create \
  -g "$RG_NAME" \
  -s "$SQL_SERVER_NAME" \
  -n "$DB_NAME" \
  --service-objective S0 \
  -o json > .deploy-sql-db.json

wait_for_condition \
  "SQL DB '$DB_NAME' Online" \
  "az sql db show -g $RG_NAME -s $SQL_SERVER_NAME -n $DB_NAME --query status -o tsv" \
  "Online" \
  900 10

########################################
# Azure Container Registry + Images
########################################

echo "Create Azure Container Registry '$CONTAINER_REGISTRY'"

az acr create \
  -g "$RG_NAME" \
  -n "$CONTAINER_REGISTRY" \
  --sku Basic \
  -l "$LOCATION" \
  -o json > .deploy-acr.json

ACR_LOGIN_SERVER=$(az acr show -n "$CONTAINER_REGISTRY" --query loginServer -o tsv)

echo "Logging in to ACR '$ACR_LOGIN_SERVER'"
az acr login -n "$CONTAINER_REGISTRY" > .deploy-acr-login.json

DATALOADER_TAG="${DATALOADER_TAG:-sbx}"
FUNCTIONS_API_TAG="${FUNCTIONS_API_TAG:-sbx}"

echo "Build and push DataLoader image"
docker build \
  -f "$REPO_ROOT/src/DataLoader/Dockerfile" \
  -t "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" \
  "$REPO_ROOT" > .deploy-dataloader-build.json
docker push "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" > .deploy-dataloader-push.json

echo "Build and push Functions API image"
docker build \
  -f "$REPO_ROOT/src/FunctionsApi/Dockerfile" \
  -t "$ACR_LOGIN_SERVER/functions-api:$FUNCTIONS_API_TAG" \
  "$REPO_ROOT" > .deploy-functions-api-build.json
docker push "$ACR_LOGIN_SERVER/functions-api:$FUNCTIONS_API_TAG" > .deploy-functions-api-push.json

########################################
# Container Apps Environment + Jobs
########################################

CONTAINERAPPS_ENV_NAME="${CONTAINERAPPS_ENV_NAME:-ppp-globe-ca-env}"

echo "Create Container Apps environment '$CONTAINERAPPS_ENV_NAME'"

az containerapp env create \
  -g "$RG_NAME" \
  -n "$CONTAINERAPPS_ENV_NAME" \
  -l "$LOCATION" \
  -o json > .deploy-ca-env.json

echo "Create DB initializer job (sqlcmd-based, similar to docker-compose)"

# Read SQL file and collapse newlines to reduce risk of shell parsing issues
DB_INIT_SQL=$(tr '\n' ' ' < "$REPO_ROOT/sql_db_init/01-init.sql")

az containerapp job create \
  --name "ppp-globe-db-init-job" \
  --resource-group "$RG_NAME" \
  --environment "$CONTAINERAPPS_ENV_NAME" \
  --trigger-type Manual \
  --replica-timeout 600 \
  --replica-retry-limit 1 \
  --image "mcr.microsoft.com/mssql-tools" \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "SA_PASSWORD=$SA_PASSWORD" \
  --command "/opt/mssql-tools/bin/sqlcmd" "-S" "$SQL_SERVER_NAME.database.windows.net" "-U" "$SA_USERNAME" "-P" "$SA_PASSWORD" "-d" "$DB_NAME" "-Q" "$DB_INIT_SQL" \
  -o json > .deploy-db-init-job.json

echo "Create DataLoader job"

az containerapp job create \
  --name "ppp-globe-dataloader-job" \
  --resource-group "$RG_NAME" \
  --environment "$CONTAINERAPPS_ENV_NAME" \
  --trigger-type Manual \
  --replica-timeout 1800 \
  --replica-retry-limit 1 \
  --image "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --cpu 0.5 \
  --memory 1Gi \
  --env-vars \
    "ConnectionStrings__PppDb=Server=$SQL_SERVER_NAME.database.windows.net,$DB_PORT;Database=$DB_NAME;User Id=$SA_USERNAME;Password=$SA_PASSWORD;TrustServerCertificate=True;" \
  -o json > .deploy-dataloader-job.json

########################################
# Run DB initializer and DataLoader
########################################

echo "Run DB initializer job"
az containerapp job start \
  --name "ppp-globe-db-init-job" \
  --resource-group "$RG_NAME" \
  -o json > .deploy-db-init-job-start.json

echo "Run DataLoader job"
az containerapp job start \
  --name "ppp-globe-dataloader-job" \
  --resource-group "$RG_NAME" \
  -o json > .deploy-dataloader-job-start.json

########################################
# Azure Functions (container-based)
########################################

echo "Create Storage Account '$STORAGE_ACCOUNT_NAME' for Functions"

az storage account create \
  -g "$RG_NAME" \
  -n "$STORAGE_ACCOUNT_NAME" \
  -l "$LOCATION" \
  --sku Standard_LRS \
  -o json > .deploy-storage-account.json

echo "Create Function App '$FUNCTION_APP_NAME'"

az functionapp create \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --storage-account "$STORAGE_ACCOUNT_NAME" \
  --consumption-plan-location "$LOCATION" \
  --runtime dotnet-isolated \
  --functions-version 4 \
  --assign-identity \
  -o json > .deploy-functionapp-create.json

echo "Configure Function App to use container image"

az functionapp config container set \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --docker-custom-image-name "$ACR_LOGIN_SERVER/functions-api:$FUNCTIONS_API_TAG" \
  --docker-registry-server-url "https://$ACR_LOGIN_SERVER" \
  -o json > .deploy-functionapp-container.json

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
  -o json > .deploy-swa-create.json

echo "Upload Static Web App content from src/Frontend"

az staticwebapp upload \
  -n "$SWA_NAME" \
  -g "$RG_NAME" \
  --source "$REPO_ROOT/src/Frontend" \
  -o json > .deploy-swa-upload.json

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
