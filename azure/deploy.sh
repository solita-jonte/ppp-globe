#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/../.env"

########################################

echo "Create Resource Group"

az deployment group create \
  -g "$RG_NAME" \
  -n "$NET_NAME" \
  -o json

# TODO: check result or wait for it to complete

########################################

echo "Create Azure SQL Database"

az sql db create \
  -g "$RG_NAME" \
  -s "$SQL_SERVER_NAME" \
  -n "$SQL_DB_NAME" \
  --service-objective S0

wait_for_condition \
  "SQL DB '$SQL_DB_NAME' Online" \
  "az sql db show -g $RG_NAME -s $SQL_SERVER_NAME -n $SQL_DB_NAME --query status -o tsv" \
  "Online" \
  900 10

########################################

echo "Create Azure Container Registry and Push"

# TODO: build and push the DB init container, the DataLoader container, and the FunctionApi container.
# az acr login -n "$CONTAINER_REGISTRY"
# docker build -t "$CONTAINER_REGISTRY.azurecr.io/dataloader:sbx" .
# docker push "$CONTAINER_REGISTRY.azurecr.io/dataloader:sbx"

########################################

echo "Run DB initializer"

az containerapp job start \
  --name "ppp-globe-db-init-job" \
  --resource-group "$RG_NAME"

# TODO: wait for completion/termination

########################################

echo "Run data loader"

az containerapp job start \
  --name "ppp-globe-dataloader-job" \
  --resource-group "$RG_NAME"

# TODO: wait for completion/termination

########################################

echo "Start Azure Functions for serving data"

# TODO:
# az functionapp create ...

########################################

echo "Start Azure Static Web App for serving frontend"

API_BASE_URL=$(az functionapp show \
    -g "$RG_NAME" \
    -n "$FUNCTION_APP_NAME" \
    --query defaultHostName -o tsv)
API_BASE_URL="https://$API_BASE_URL/api"
cp src/Frontend/js/config.template.js src/Frontend/js/config.js
sed -i "s|__API_BASE_URL__|$API_BASE_URL|g" src/Frontend/js/config.js

swa deploy \
  ./src/Frontend
  -g "$RG_NAME" \
  -n "$SWA_NAME"

########################################

SWA_HOSTNAME=$(az staticwebapp show \
  -n "$SWA_NAME" \
  -g "$RG_NAME" \
  --query "defaultHostname" \
  -o tsv)

FRONTEND_URL="https://$SWA_HOSTNAME"
echo "Point your browser towards: $FRONTEND_URL"
