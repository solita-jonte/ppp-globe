RG_NAME="ppp-globe-rg"
NET_NAME="ppp-globe-infra"
SQL_SERVER_NAME="ppp-globe-sql"
CONTAINER_REGISTRY="acr-ppp-globe"
SWA_NAME="ppp-globe-swa"
FUNCTION_APP_NAME="ppp-globe-func"
STORAGE_ACCOUNT_NAME="pppglobestorage" # must be globally unique, adjust if needed
LOCATION="${LOCATION:-westeurope}"      # can be overridden via .env

ensure_az_and_swa() {
  # Check that az is installed
  if ! command -v az >/dev/null 2>&1; then
    echo "Error: Azure CLI (az) is not installed or not on PATH." >&2
    echo "Install it like so: winget install -e --id Microsoft.AzureCLI" >&2
    exit 1
  fi

  # Check that user is logged in to az
  if ! az account show -o none >/dev/null 2>&1; then
    echo "Error: You are not logged in to Azure CLI." >&2
    echo "Run: az login" >&2
    exit 1
  fi
}

wait_for_condition() {
  local description="$1"
  local cmd="$2"
  local expected="$3"
  local timeout_seconds="${4:-600}" # default 10 min
  local interval_seconds="${5:-10}"

  echo "Waiting for: $description"

  local start
  start=$(date +%s)
  while true; do
    local now
    now=$(date +%s)
    local elapsed=$((now - start))
    if (( elapsed > timeout_seconds )); then
      echo "Timeout waiting for: $description"
      return 1
    fi

    # Evaluate command
    local value
    value=$(eval "$cmd")

    if [[ "$value" == "$expected" ]]; then
      echo "Condition met: $description"
      return 0
    fi

    echo "Still waiting for: $description (current: '$value', expected: '$expected')"
    sleep "$interval_seconds"
  done
}
