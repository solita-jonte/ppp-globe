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

########################################
# Resource Group
########################################

echo "Create Resource Group '$RG_NAME' in '$LOCATION'"

az group create \
  -n "$RG_NAME" \
  -l "$LOCATION" \
  --tags Owner="$OWNER_TAG" DueDate="$DUEDATE_TAG" \
  -o json > .deploy-log-rg.json

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
  -o json > .deploy-log-sql-server.json

echo "Create Azure SQL Database '$DB_NAME'"

az sql db create \
  -g "$RG_NAME" \
  -s "$SQL_SERVER_NAME" \
  -n "$DB_NAME" \
  --service-objective S0 \
  -o json > .deploy-log-sql-db.json

wait_for_condition \
  "SQL DB '$DB_NAME' Online" \
  "az sql db show -g $RG_NAME -s $SQL_SERVER_NAME -n $DB_NAME --query status -o tsv" \
  "Online" \
  900 10

echo "Open SQL DB firewall"

az sql server firewall-rule create \
  --resource-group $RG_NAME \
  --server $SQL_SERVER_NAME \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

########################################
# Azure Container Registry + Images
########################################

echo "Create Azure Container Registry '$CONTAINER_REGISTRY'"

az acr create \
  -g "$RG_NAME" \
  -n "$CONTAINER_REGISTRY" \
  --sku Basic \
  -l "$LOCATION" \
  -o json > .deploy-log-acr.json

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
DB_INIT_TAG="${DB_INIT_TAG:-sbx}"
FUNCTIONS_API_TAG="${FUNCTIONS_API_TAG:-sbx}"
FRONTEND_TAG="${FRONTEND_TAG:-sbx}"

echo "Build and push DB init image"
docker build \
  -f "$REPO_ROOT/sql_init/Dockerfile" \
  -t "$ACR_LOGIN_SERVER/db-init:$DB_INIT_TAG" \
  "$REPO_ROOT" > .deploy-log-db-init-build.txt
docker push "$ACR_LOGIN_SERVER/db-init:$DB_INIT_TAG" > .deploy-log-db-init-push.txt

echo "Build and push DataLoader image"
docker build \
  -f "$REPO_ROOT/src/DataLoader/Dockerfile" \
  -t "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" \
  "$REPO_ROOT" > .deploy-log-dataloader-build.txt
docker push "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" > .deploy-log-dataloader-push.txt

########################################
# Container Apps Environment + Jobs
########################################

CONTAINERAPPS_ENV_NAME="${CONTAINERAPPS_ENV_NAME:-ppp-globe-ca-env}"

echo "Create Container Apps environment '$CONTAINERAPPS_ENV_NAME'"

az containerapp env create \
  -g "$RG_NAME" \
  -n "$CONTAINERAPPS_ENV_NAME" \
  -l "$LOCATION" \
  -o json > .deploy-log-ca-env.json

echo "Create DB initializer job (image-based)"

DB_INIT_JOB_NAME=ppp-globe-db-init-job

az containerapp job create \
  --name "$DB_INIT_JOB_NAME" \
  --resource-group "$RG_NAME" \
  --environment "$CONTAINERAPPS_ENV_NAME" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --trigger-type Manual \
  --replica-timeout 600 \
  --replica-retry-limit 1 \
  --replica-completion-count 1 \
  --parallelism 1 \
  --image "$ACR_LOGIN_SERVER/db-init:$DB_INIT_TAG" \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "SA_PASSWORD=$SA_PASSWORD" \
    "DB_NAME=$DB_NAME" \
    "SQL_SERVER_HOST=$SQL_SERVER_NAME.database.windows.net" \
    "SQL_SERVER_USER=$SA_USERNAME" \
  -o json > .deploy-log-db-init-job.json

echo "Create DataLoader job"

DATALOADER_JOB_NAME=ppp-globe-dataloader-job

az containerapp job create \
  --name "$DATALOADER_JOB_NAME" \
  --resource-group "$RG_NAME" \
  --environment "$CONTAINERAPPS_ENV_NAME" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --trigger-type Manual \
  --replica-timeout 1800 \
  --replica-retry-limit 1 \
  --replica-completion-count 1 \
  --parallelism 1 \
  --image "$ACR_LOGIN_SERVER/dataloader:$DATALOADER_TAG" \
  --cpu 0.5 \
  --memory 1Gi \
  --env-vars \
    "ConnectionStrings__PppDb=Server=$SQL_SERVER_NAME.database.windows.net,$DB_PORT;Database=$DB_NAME;User Id=$SA_USERNAME;Password=$SA_PASSWORD;TrustServerCertificate=True;" \
  -o json > .deploy-log-dataloader-job.json

########################################
# Run DB initializer and wait for completion, then run DataLoader
########################################

echo "Run DB initializer job"
az containerapp job start \
  --name "$DB_INIT_JOB_NAME" \
  --resource-group "$RG_NAME" \
  -o json > .deploy-log-db-init-job-start.json

# Wait until the init job has completed (Succeeded or Failed)
wait_for_job_completion "$DB_INIT_JOB_NAME" "$RG_NAME" 900 10

echo "Run DataLoader job"
az containerapp job start \
  --name "$DATALOADER_JOB_NAME" \
  --resource-group "$RG_NAME" \
  -o json > .deploy-log-dataloader-job-start.json

########################################
# Azure Functions (container-based)
########################################

echo "Create Storage Account '$STORAGE_ACCOUNT_NAME' for Functions"

az storage account create \
  -g "$RG_NAME" \
  -n "$STORAGE_ACCOUNT_NAME" \
  -l "$LOCATION" \
  --sku Standard_LRS \
  -o json > .deploy-log-storage-account.json

echo "Create Function App '$FUNCTION_APP_NAME'"

az functionapp create \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --storage-account "$STORAGE_ACCOUNT_NAME" \
  --consumption-plan-location "$LOCATION" \
  --functions-version 4 \
  --runtime dotnet-isolated \
  --os-type Linux \
  -o json > .deploy-log-functionapp-create.json

echo "Configure Function App env vars"

# First configure app settings (environment variables)
az functionapp config appsettings set \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --settings \
    "FUNCTIONS_WORKER_RUNTIME=dotnet-isolated" \
    "FUNCTIONS_EXTENSION_VERSION=~4" \
    "ConnectionStrings__PppDb=Server=tcp:$SQL_SERVER_NAME.database.windows.net,$DB_PORT;Database=$DB_NAME;Uid=$SA_USERNAME;Pwd=$SA_PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;" \
  -o json > .deploy-log-functionapp-appsettings.json

az functionapp cors add \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --allowed-origins 'https://*' \
  -o json > .deploy-log-functionapp-cors.json

echo "Publish Function App"

pushd src/FunctionsApi
func azure functionapp publish "$FUNCTION_APP_NAME" --dotnet-isolated
popd

API_BASE_HOST=$(az functionapp show \
  -g "$RG_NAME" \
  -n "$FUNCTION_APP_NAME" \
  --query defaultHostName -o tsv)
API_BASE_URL="https://$API_BASE_HOST/api"

########################################
# Frontend Container App build + deploy
########################################

FRONTEND_APP_NAME="${FRONTEND_APP_NAME:-ppp-globe-frontend}"

echo "Build and push Frontend image"
docker build \
  -f "$REPO_ROOT/src/Frontend/Dockerfile" \
  -t "$ACR_LOGIN_SERVER/frontend:$FRONTEND_TAG" \
  --build-arg API_BASE_URL="$API_BASE_URL" \
  "$REPO_ROOT" > .deploy-log-frontend-build.txt
docker push "$ACR_LOGIN_SERVER/frontend:$FRONTEND_TAG" > .deploy-log-frontend-push.txt

echo "Create Frontend Container App '$FRONTEND_APP_NAME'"

az containerapp create \
  --name "$FRONTEND_APP_NAME" \
  --resource-group "$RG_NAME" \
  --environment "$CONTAINERAPPS_ENV_NAME" \
  --image "$ACR_LOGIN_SERVER/frontend:$FRONTEND_TAG" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --ingress external \
  --target-port 4173 \
  --transport auto \
  -o json > .deploy-log-frontend-ca.json

########################################
# Output frontend URL
########################################

FRONTEND_FQDN=$(az containerapp show \
  --name "$FRONTEND_APP_NAME" \
  --resource-group "$RG_NAME" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

FRONTEND_URL="https://$FRONTEND_FQDN"
echo "Deployment complete."
echo "Point your browser towards: $FRONTEND_URL"
echo "Run ./azure/teardown.sh when done to remove all Azure resources."
