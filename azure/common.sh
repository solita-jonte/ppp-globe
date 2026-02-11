RG_NAME="ppp-globe-rg"
NET_NAME="ppp-globe-infra"
SQL_SERVER_NAME="ppp-globe-sql"
SQL_DB_NAME="db"
CONTAINER_REGISTRY="acr-ppp-globe"
SWA_NAME="ppp-globe-swa"


wait_for_condition() {
  local description="$1"
  local cmd="$2"
  local expected="$3"
  local timeout_seconds="${4:-600}" # default 10 min
  local interval_seconds="${5:-10}"

  echo "Waiting for: $description"

  local start=$(date +%s)
  while true; do
    local now=$(date +%s)
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
