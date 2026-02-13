#!/bin/bash

set -euo pipefail

# Directory of this script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Repo root is parent of scripts/
REPO_ROOT="$SCRIPT_DIR/.."

FRONTEND_DIR="$REPO_ROOT/src/Frontend"
TARGET_FILE="$FRONTEND_DIR/countries.geojson"

# Public world countries GeoJSON.
# You can change this to another source if you prefer.
SOURCE_URL="https://raw.githubusercontent.com/holtzy/D3-graph-gallery/master/DATA/world.geojson"

echo "Downloading countries GeoJSON from:"
echo "  $SOURCE_URL"
echo "Saving to:"
echo "  $TARGET_FILE"

curl -fsSL "$SOURCE_URL" -o "$TARGET_FILE"

echo "Done. File saved at $TARGET_FILE"
