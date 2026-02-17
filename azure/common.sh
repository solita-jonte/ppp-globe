RG_NAME="ppp-globe-rg"
NET_NAME="ppp-globe-infra"
SQL_SERVER_NAME="ppp-globe-sql"
# Azure Container Registry name cannot contain dashes; use only lowercase letters and numbers.
CONTAINER_REGISTRY="acrpppglobe"
SWA_NAME="ppp-globe-swa"
FUNCTION_APP_NAME="ppp-globe-func"
STORAGE_ACCOUNT_NAME="pppglobestorage" # must be globally unique, adjust if needed
LOCATION="${LOCATION:-westeurope}"      # can be overridden via .env

# Sanitize a string to be safe for Azure resource names / tags where needed.
# - Lowercase
# - Replace any non [a-z0-9-] with '-'
# - Collapse multiple '-' into one
# - Trim leading/trailing '-'
sanitize_ascii() {
  local input="$1"
  # to lowercase
  local s
  s=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
  # replace non allowed chars with '-'
  s=$(printf '%s' "$s" | sed 's/[^a-z0-9-]/-/g')
  # collapse multiple '-'
  s=$(printf '%s' "$s" | sed 's/-\{2,\}/-/g')
  # trim leading/trailing '-'
  s=$(printf '%s' "$s" | sed 's/^-*//; s/-*$//')
  printf '%s' "$s"
}

ensure_az() {
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

ensure_docker() {
  # Check that docker CLI is installed
  if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed or not on PATH." >&2
    echo "Install Docker Desktop and ensure the docker CLI is available." >&2
    exit 1
  fi

  # Check that Docker daemon (Docker Desktop) is running
  if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon does not appear to be running." >&2
    echo "Start Docker Desktop and wait until it is fully up, then retry." >&2
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

# Wait for a Container Apps job to have at least one run in a terminal state.
# Succeeds when any run has status 'Succeeded' or 'Failed'.
# Fails on timeout or if the last seen terminal status is 'Failed'.
#
# Usage:
#   wait_for_job_completion "job-name" "resource-group" [timeout_seconds] [interval_seconds]
wait_for_job_completion() {
  local job_name="$1"
  local resource_group="$2"
  local timeout_seconds="${3:-900}"   # default 15 min
  local interval_seconds="${4:-10}"

  echo "Waiting for Container Apps job '$job_name' in resource group '$resource_group' to complete..."

  local start
  start=$(date +%s)
  local last_status=""

  while true; do
    local now
    now=$(date +%s)
    local elapsed=$((now - start))
    if (( elapsed > timeout_seconds )); then
      echo "Timeout waiting for job '$job_name' to complete. Last known status: '$last_status'" >&2
      return 1
    fi

    # Query the most recent run status (if any)
    local status
    status=$(az containerapp job execution list \
      --name "$job_name" \
      --resource-group "$resource_group" \
      --query "[0].properties.status" \
      -o tsv 2>/dev/null || echo "")

    if [[ -z "$status" ]]; then
      echo "No executions found yet for job '$job_name'. Waiting..."
      sleep "$interval_seconds"
      continue
    fi

    last_status="$status"
    echo "Latest execution status for job '$job_name': $status"

    case "$status" in
      Succeeded)
        echo "Job '$job_name' completed successfully."
        return 0
        ;;
      Failed)
        echo "Job '$job_name' failed." >&2
        return 1
        ;;
      *)
        # Pending, Running, etc.
        sleep "$interval_seconds"
        ;;
    esac
  done
}
