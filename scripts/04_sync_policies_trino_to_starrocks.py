#!/usr/bin/env python3
"""
Sync Ranger policies from Trino service to StarRocks service.

Rules:
1. Only sync policies related to 'iceberg' catalog
2. For Access policies (policyType=0) with multiple permissions -> only sync SELECT
3. Sync all Masking (policyType=1) and Row-Level Filter (policyType=2) policies fully
4. Transform users: username@ssi.com.vn -> username
"""

import argparse
import json
import logging
import re
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from base64 import b64encode

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

# Mapping from Trino access types to StarRocks access types
TRINO_TO_STARROCKS_ACCESS = {
    "select": "select",
    "insert": "insert",
    "delete": "delete",
    "drop": "drop",
    "alter": "alter",
    "use": "usage",
    "show": None,  # no direct equivalent, skip
    "create": "create table",
    "grant": "grant",
}


def ranger_api(base_url, path, user, password, method="GET", data=None):
    """Call Ranger REST API."""
    url = f"{base_url}{path}"
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    credentials = b64encode(f"{user}:{password}".encode()).decode()
    headers["Authorization"] = f"Basic {credentials}"

    body = json.dumps(data).encode() if data else None
    req = Request(url, data=body, headers=headers, method=method)

    try:
        with urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except HTTPError as e:
        error_body = e.read().decode() if e.fp else ""
        log.error("API %s %s -> HTTP %s: %s", method, url, e.code, error_body)
        raise


def get_service_policies(base_url, service_name, user, password):
    """Get all policies for a Ranger service."""
    policies = ranger_api(
        base_url,
        f"/service/public/v2/api/service/{service_name}/policy",
        user,
        password,
    )
    return policies


def get_existing_policies(base_url, service_name, user, password):
    """Get existing policies in target service, indexed by name."""
    policies = get_service_policies(base_url, service_name, user, password)
    return {p["name"]: p for p in policies}


def strip_email_domain(username):
    """Transform username@ssi.com.vn -> username."""
    return re.sub(r"@ssi\.com\.vn$", "", username)


def transform_users(users):
    """Strip @ssi.com.vn from all usernames."""
    return [strip_email_domain(u) for u in users]


def sync_roles(base_url, user, password):
    """Sync roles: add stripped-domain users alongside originals.

    Ranger roles are shared between Trino and StarRocks. Trino needs
    username@ssi.com.vn, StarRocks needs username. We keep both in the role
    so both engines can match their users.

    Returns set of role names that were synced.
    """
    log.info("Fetching Ranger roles...")
    try:
        roles = ranger_api(base_url, "/service/public/v2/api/roles", user, password)
    except Exception:
        log.warning("Could not fetch roles, skipping role sync")
        return set()

    synced = set()
    for role in roles:
        role_name = role.get("name", "")
        if not role_name:
            continue

        original_users = role.get("users", [])
        existing_names = {u.get("name", "") for u in original_users}

        # Add stripped-domain users alongside originals
        new_users = list(original_users)
        for u in original_users:
            stripped = strip_email_domain(u.get("name", ""))
            if stripped != u.get("name", "") and stripped not in existing_names:
                new_users.append({"name": stripped, "isAdmin": u.get("isAdmin", False)})
                existing_names.add(stripped)

        if len(new_users) == len(original_users):
            log.info("Role '%s' already has all users, skipping", role_name)
            synced.add(role_name)
            continue

        role["users"] = new_users
        try:
            ranger_api(
                base_url,
                f"/service/public/v2/api/roles/{role['id']}",
                user,
                password,
                method="PUT",
                data=role,
            )
            log.info("SYNCED role '%s' with users: %s",
                     role_name, [u["name"] for u in new_users])
            synced.add(role_name)
        except Exception:
            log.error("Failed to sync role '%s'", role_name)

    return synced


def is_iceberg_policy(policy):
    """Check if policy is related to iceberg catalog."""
    resources = policy.get("resources", {})
    catalog_res = resources.get("catalog", {})
    values = catalog_res.get("values", [])
    # Only match explicit 'iceberg' catalog, not wildcard '*'
    for v in values:
        if v.lower() == "iceberg":
            return True
    return False


def has_catalog_resource(policy):
    """Check if policy has a catalog resource (relevant for iceberg filtering)."""
    return "catalog" in policy.get("resources", {})


def needs_usage_permission(resources):
    """Check if resources target catalog or database level (StarRocks requires 'usage' to access)."""
    resource_keys = set(resources.keys())
    # Catalog-only or catalog+database policies need usage for StarRocks visibility
    return resource_keys in (
        {"catalog"},
        {"catalog", "schema"},
        {"catalog", "database"},
    )


def transform_access_policy(policy):
    """
    Transform an Access policy (policyType=0):
    - Only keep SELECT permission (+ usage on catalog/database level for StarRocks visibility)
    - Transform users
    """
    new_policy = create_base_policy(policy)
    add_usage = needs_usage_permission(policy.get("resources", {}))

    # Transform policyItems - only keep SELECT
    new_items = []
    for item in policy.get("policyItems", []):
        # Filter accesses to only select
        select_accesses = [
            a for a in item.get("accesses", [])
            if a.get("type") == "select"
        ]
        # Also check for 'use' (Trino equivalent of usage)
        use_accesses = [
            a for a in item.get("accesses", [])
            if a.get("type") == "use"
        ]
        if not select_accesses and not use_accesses:
            continue

        accesses = []
        if select_accesses:
            accesses.append({"type": "select", "isAllowed": True})
        if add_usage:
            accesses.append({"type": "usage", "isAllowed": True})

        new_item = {
            "accesses": accesses,
            "users": transform_users(item.get("users", [])),
            "groups": item.get("groups", []),
            "roles": item.get("roles", []),
            "conditions": item.get("conditions", []),
            "delegateAdmin": item.get("delegateAdmin", False),
        }
        new_items.append(new_item)

    if not new_items:
        return None  # No applicable permissions found, skip this policy

    new_policy["policyItems"] = new_items
    return new_policy


def transform_masking_policy(policy):
    """
    Transform a Data Masking policy (policyType=1):
    - Sync fully
    - Transform users
    """
    new_policy = create_base_policy(policy)

    new_items = []
    for item in policy.get("dataMaskPolicyItems", []):
        new_item = {
            "accesses": item.get("accesses", []),
            "users": transform_users(item.get("users", [])),
            "groups": item.get("groups", []),
            "roles": item.get("roles", []),
            "conditions": item.get("conditions", []),
            "delegateAdmin": item.get("delegateAdmin", False),
            "dataMaskInfo": item.get("dataMaskInfo", {}),
        }
        new_items.append(new_item)

    new_policy["dataMaskPolicyItems"] = new_items
    return new_policy


def transform_rowfilter_policy(policy):
    """
    Transform a Row Filter policy (policyType=2):
    - Sync fully
    - Transform users
    """
    new_policy = create_base_policy(policy)

    new_items = []
    for item in policy.get("rowFilterPolicyItems", []):
        new_item = {
            "accesses": item.get("accesses", []),
            "users": transform_users(item.get("users", [])),
            "groups": item.get("groups", []),
            "roles": item.get("roles", []),
            "conditions": item.get("conditions", []),
            "delegateAdmin": item.get("delegateAdmin", False),
            "rowFilterInfo": item.get("rowFilterInfo", {}),
        }
        new_items.append(new_item)

    new_policy["rowFilterPolicyItems"] = new_items
    return new_policy


def map_resources_trino_to_starrocks(resources):
    """Map Trino resource names to StarRocks resource names.

    Trino hierarchy:  catalog -> schema  -> table -> column
    StarRocks hierarchy: catalog -> database -> table -> column
    """
    RESOURCE_MAP = {
        "schema": "database",
        # catalog, table, column are the same
    }
    mapped = {}
    for key, value in resources.items():
        new_key = RESOURCE_MAP.get(key, key)
        mapped[new_key] = value
    return mapped


def create_base_policy(source_policy):
    """Create a base StarRocks policy from a Trino source policy."""
    # Prefix name to avoid collisions with existing StarRocks policies
    name = f"sync-trino: {source_policy['name']}"

    return {
        "service": "",  # Will be set later
        "name": name,
        "policyType": source_policy.get("policyType", 0),
        "isEnabled": source_policy.get("isEnabled", True),
        "isAuditEnabled": source_policy.get("isAuditEnabled", True),
        "resources": map_resources_trino_to_starrocks(source_policy.get("resources", {})),
        "description": f"Synced from Trino policy: {source_policy['name']} (id={source_policy.get('id')})",
    }


def sync_policies(
    ranger_url,
    ranger_user,
    ranger_pass,
    trino_service,
    starrocks_service,
    dry_run=False,
):
    """Main sync logic."""
    # Sync roles first (transform users in roles)
    if not dry_run:
        sync_roles(ranger_url, ranger_user, ranger_pass)
    else:
        log.info("DRY-RUN: skipping role sync")

    log.info("Fetching Trino policies from service '%s'...", trino_service)
    trino_policies = get_service_policies(ranger_url, trino_service, ranger_user, ranger_pass)
    log.info("Found %d total Trino policies", len(trino_policies))

    # Filter to iceberg-related policies only
    iceberg_policies = [
        p for p in trino_policies
        if has_catalog_resource(p) and is_iceberg_policy(p)
    ]
    log.info("Found %d iceberg-related policies", len(iceberg_policies))

    # Get existing synced policies in StarRocks
    existing = get_existing_policies(ranger_url, starrocks_service, ranger_user, ranger_pass)
    log.info("Found %d existing StarRocks policies", len(existing))

    created = 0
    updated = 0
    skipped = 0

    for policy in iceberg_policies:
        policy_type = policy.get("policyType", 0)
        policy_name = policy.get("name", "unknown")

        if policy_type == 0:
            transformed = transform_access_policy(policy)
            if transformed is None:
                log.info("SKIP (no select): %s", policy_name)
                skipped += 1
                continue
        elif policy_type == 1:
            transformed = transform_masking_policy(policy)
        elif policy_type == 2:
            transformed = transform_rowfilter_policy(policy)
        else:
            log.warning("Unknown policy type %d for '%s', skipping", policy_type, policy_name)
            skipped += 1
            continue

        transformed["service"] = starrocks_service
        sr_name = transformed["name"]

        if dry_run:
            log.info("DRY-RUN would sync: [type=%d] %s -> %s", policy_type, policy_name, sr_name)
            log.debug("  Payload: %s", json.dumps(transformed, indent=2))
            continue

        if sr_name in existing:
            # Update existing policy
            existing_id = existing[sr_name]["id"]
            transformed["id"] = existing_id
            try:
                ranger_api(
                    ranger_url,
                    f"/service/public/v2/api/policy/{existing_id}",
                    ranger_user,
                    ranger_pass,
                    method="PUT",
                    data=transformed,
                )
                log.info("UPDATED [type=%d]: %s (id=%d)", policy_type, sr_name, existing_id)
                updated += 1
            except HTTPError:
                log.error("Failed to update policy: %s", sr_name)
        else:
            # Create new policy
            try:
                result = ranger_api(
                    ranger_url,
                    "/service/public/v2/api/policy",
                    ranger_user,
                    ranger_pass,
                    method="POST",
                    data=transformed,
                )
                log.info("CREATED [type=%d]: %s (id=%s)", policy_type, sr_name, result.get("id"))
                created += 1
            except HTTPError:
                log.error("Failed to create policy: %s", sr_name)

    log.info("=== Sync Summary ===")
    log.info("Created: %d, Updated: %d, Skipped: %d", created, updated, skipped)


def main():
    parser = argparse.ArgumentParser(description="Sync Ranger policies from Trino to StarRocks")
    parser.add_argument("--ranger-url", default="http://localhost:6080", help="Ranger Admin URL")
    parser.add_argument("--ranger-user", default="admin", help="Ranger admin username")
    parser.add_argument("--ranger-pass", default="rangerR0cks!", help="Ranger admin password")
    parser.add_argument("--trino-service", default="trino", help="Trino service name in Ranger")
    parser.add_argument("--starrocks-service", default="starrocks", help="StarRocks service name in Ranger")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without applying")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    sync_policies(
        args.ranger_url,
        args.ranger_user,
        args.ranger_pass,
        args.trino_service,
        args.starrocks_service,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
