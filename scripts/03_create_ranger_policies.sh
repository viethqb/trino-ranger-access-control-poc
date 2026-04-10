#!/bin/bash
# Create Ranger policies for Trino Iceberg catalog
# Usage: bash scripts/03_create_ranger_policies.sh

RANGER_URL="http://localhost:6080"
RANGER_USER="admin"
RANGER_PASS="rangerR0cks!"
SERVICE_NAME="trino"

create_policy() {
    local payload="$1"
    local description="$2"
    echo "Creating policy: $description"
    response=$(curl -s -w "\n%{http_code}" -u "${RANGER_USER}:${RANGER_PASS}" \
        -H "Content-Type: application/json" \
        -X POST "${RANGER_URL}/service/public/v2/api/policy" \
        -d "$payload")
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    if [ "$http_code" = "200" ]; then
        echo "  -> OK (id=$(echo "$body" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id","?"))' 2>/dev/null))"
    else
        echo "  -> HTTP $http_code: $body"
    fi
}

echo "=== 1. Access Policies ==="

# Policy: Allow users to use iceberg catalog
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - catalog usage",
  "policyType": 0,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false}
  },
  "policyItems": [{
    "accesses": [
      {"type": "use", "isAllowed": true},
      {"type": "show", "isAllowed": true}
    ],
    "users": ["analyst1@ssi.com.vn", "analyst2@ssi.com.vn"],
    "groups": [],
    "delegateAdmin": false
  }]
}' "iceberg - catalog usage"

# Policy: Allow users to access tpch schema
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - tpch schema access",
  "policyType": 0,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false}
  },
  "policyItems": [{
    "accesses": [
      {"type": "use", "isAllowed": true},
      {"type": "show", "isAllowed": true},
      {"type": "select", "isAllowed": true}
    ],
    "users": ["analyst1@ssi.com.vn", "analyst2@ssi.com.vn"],
    "groups": [],
    "delegateAdmin": false
  }]
}' "iceberg - tpch schema access"

# Policy: Allow SELECT on all tables in iceberg.tpch for analyst1
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - tpch tables select",
  "policyType": 0,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["*"], "isExcludes": false, "isRecursive": false}
  },
  "policyItems": [{
    "accesses": [
      {"type": "select", "isAllowed": true},
      {"type": "show", "isAllowed": true}
    ],
    "users": ["analyst1@ssi.com.vn"],
    "groups": [],
    "delegateAdmin": false
  }, {
    "accesses": [
      {"type": "select", "isAllowed": true},
      {"type": "show", "isAllowed": true},
      {"type": "insert", "isAllowed": true},
      {"type": "delete", "isAllowed": true}
    ],
    "users": ["analyst2@ssi.com.vn"],
    "groups": [],
    "delegateAdmin": false
  }]
}' "iceberg - tpch tables select"

# Policy: Column-level SELECT on all columns
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - tpch columns select",
  "policyType": 0,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["*"], "isExcludes": false, "isRecursive": false},
    "column": {"values": ["*"], "isExcludes": false, "isRecursive": false}
  },
  "policyItems": [{
    "accesses": [
      {"type": "select", "isAllowed": true},
      {"type": "show", "isAllowed": true}
    ],
    "users": ["analyst1@ssi.com.vn", "analyst2@ssi.com.vn"],
    "groups": [],
    "delegateAdmin": false
  }]
}' "iceberg - tpch columns select"

echo ""
echo "=== 2. Data Masking Policies ==="

# Masking: Mask customer phone column for analyst1
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - mask customer phone",
  "policyType": 1,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["customer"], "isExcludes": false, "isRecursive": false},
    "column": {"values": ["phone"], "isExcludes": false, "isRecursive": false}
  },
  "dataMaskPolicyItems": [{
    "accesses": [{"type": "select", "isAllowed": true}],
    "users": ["analyst1@ssi.com.vn"],
    "groups": [],
    "dataMaskInfo": {
      "dataMaskType": "MASK"
    }
  }]
}' "iceberg - mask customer phone"

# Masking: Hash customer acctbal for analyst1
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - mask customer acctbal",
  "policyType": 1,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["customer"], "isExcludes": false, "isRecursive": false},
    "column": {"values": ["acctbal"], "isExcludes": false, "isRecursive": false}
  },
  "dataMaskPolicyItems": [{
    "accesses": [{"type": "select", "isAllowed": true}],
    "users": ["analyst1@ssi.com.vn"],
    "groups": [],
    "dataMaskInfo": {
      "dataMaskType": "MASK_NULL"
    }
  }]
}' "iceberg - mask customer acctbal"

# Masking: Mask supplier phone for analyst2
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - mask supplier phone",
  "policyType": 1,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["supplier"], "isExcludes": false, "isRecursive": false},
    "column": {"values": ["phone"], "isExcludes": false, "isRecursive": false}
  },
  "dataMaskPolicyItems": [{
    "accesses": [{"type": "select", "isAllowed": true}],
    "users": ["analyst2@ssi.com.vn"],
    "groups": [],
    "dataMaskInfo": {
      "dataMaskType": "MASK"
    }
  }]
}' "iceberg - mask supplier phone"

echo ""
echo "=== 3. Row-Level Filter Policies ==="

# Row filter: analyst1 can only see customers from nation 1 (Argentina)
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - row filter customer by nation",
  "policyType": 2,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["customer"], "isExcludes": false, "isRecursive": false}
  },
  "rowFilterPolicyItems": [{
    "accesses": [{"type": "select", "isAllowed": true}],
    "users": ["analyst1@ssi.com.vn"],
    "groups": [],
    "rowFilterInfo": {
      "filterExpr": "nationkey = 1"
    }
  }]
}' "iceberg - row filter customer by nation"

# Row filter: analyst2 can only see orders with totalprice > 1000
create_policy '{
  "service": "'"$SERVICE_NAME"'",
  "name": "iceberg - row filter orders by price",
  "policyType": 2,
  "isEnabled": true,
  "resources": {
    "catalog": {"values": ["iceberg"], "isExcludes": false, "isRecursive": false},
    "schema": {"values": ["tpch"], "isExcludes": false, "isRecursive": false},
    "table": {"values": ["orders"], "isExcludes": false, "isRecursive": false}
  },
  "rowFilterPolicyItems": [{
    "accesses": [{"type": "select", "isAllowed": true}],
    "users": ["analyst2@ssi.com.vn"],
    "groups": [],
    "rowFilterInfo": {
      "filterExpr": "totalprice > 1000"
    }
  }]
}' "iceberg - row filter orders by price"

echo ""
echo "=== Done! ==="
echo "View policies at: ${RANGER_URL} (login: admin / rangerR0cks!)"
