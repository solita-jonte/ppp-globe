#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

# Ensure required CLIs and login
ensure_az_and_swa

az group delete -n "$RG_NAME" --yes --no-wait
