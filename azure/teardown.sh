#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

# Ensure required CLIs and login
ensure_az

az group delete -n "$RG_NAME" --yes --no-wait

echo "This is going to take a long time. Check in Azure Portal to verify before re-deploying."
