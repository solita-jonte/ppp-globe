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

# Read a file into a single-line string.
# - Strips all '\r' (handles CRLF and CR)
# - Replaces all '\n' with spaces
# Usage: to_single_line "/path/to/file"
to_single_line() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "to_single_line: file not found: $file" >&2
    return 1
  fi

  # Remove carriage returns, then replace newlines with spaces.
  # Everything stays in RAM; no temp files.
  tr -d '\r' < "$file" | tr '\n' ' '
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
