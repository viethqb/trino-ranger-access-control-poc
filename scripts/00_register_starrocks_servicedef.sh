#!/bin/bash
# Register or update StarRocks service definition in Ranger
# Usage: bash scripts/00_register_starrocks_servicedef.sh
#
# This script is idempotent:
#   - If the service def does NOT exist -> CREATE
#   - If the service def already exists -> UPDATE (preserves id & version)

set -euo pipefail

RANGER_URL="${RANGER_URL:-http://localhost:6080}"
RANGER_USER="${RANGER_USER:-admin}"
RANGER_PASS="${RANGER_PASS:-rangerR0cks!}"
SERVICEDEF_FILE="$(dirname "$0")/../starrocks/ranger-servicedef-starrocks.json"

if [ ! -f "$SERVICEDEF_FILE" ]; then
    echo "ERROR: Service def file not found: $SERVICEDEF_FILE"
    exit 1
fi

echo "Checking if 'starrocks' service definition exists..."
existing=$(curl -s -w "\n%{http_code}" -u "${RANGER_USER}:${RANGER_PASS}" \
    "${RANGER_URL}/service/public/v2/api/servicedef/name/starrocks" 2>/dev/null)

http_code=$(echo "$existing" | tail -1)
body=$(echo "$existing" | sed '$d')

if [ "$http_code" = "200" ]; then
    # Service def exists -> UPDATE
    existing_id=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    existing_version=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',1))")
    echo "Found existing service def: id=$existing_id, version=$existing_version"

    # Merge id and version into local file payload
    payload=$(python3 -c "
import json, sys
with open('$SERVICEDEF_FILE') as f:
    local = json.load(f)
local['id'] = $existing_id
local['version'] = $existing_version
print(json.dumps(local))
")

    echo "Updating service definition (PUT)..."
    response=$(curl -s -w "\n%{http_code}" -u "${RANGER_USER}:${RANGER_PASS}" \
        -H "Content-Type: application/json" \
        -X PUT "${RANGER_URL}/service/public/v2/api/servicedef/${existing_id}" \
        -d "$payload")

    resp_code=$(echo "$response" | tail -1)
    resp_body=$(echo "$response" | sed '$d')

    if [ "$resp_code" = "200" ]; then
        new_version=$(echo "$resp_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))")
        echo "SUCCESS: Updated service def id=$existing_id, version=$new_version"
    else
        echo "ERROR: HTTP $resp_code"
        echo "$resp_body"
        exit 1
    fi
else
    # Service def does not exist -> CREATE
    echo "Service def not found, creating new one (POST)..."
    response=$(curl -s -w "\n%{http_code}" -u "${RANGER_USER}:${RANGER_PASS}" \
        -H "Content-Type: application/json" \
        -X POST "${RANGER_URL}/service/public/v2/api/servicedef" \
        -d @"$SERVICEDEF_FILE")

    resp_code=$(echo "$response" | tail -1)
    resp_body=$(echo "$response" | sed '$d')

    if [ "$resp_code" = "200" ]; then
        new_id=$(echo "$resp_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','?'))")
        echo "SUCCESS: Created service def id=$new_id"
    else
        echo "ERROR: HTTP $resp_code"
        echo "$resp_body"
        exit 1
    fi
fi
