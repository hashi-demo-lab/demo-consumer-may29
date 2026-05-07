#!/usr/bin/env python3
"""
Calculate the next module version based on semantic versioning rules.

Queries the Terraform Cloud API to get the current module version,
then increments it based on the release type (major, minor, or patch).
"""

import os
import sys
from typing import Optional
import requests
from packaging import version


def get_latest_version(
    tfe_hostname: str,
    org_name: str,
    module_name: str,
    provider_name: str,
    token: str
) -> Optional[str]:
    """
    Fetch the latest version of a module from Terraform Cloud.

    Returns:
        Latest version string (e.g., "1.2.3") or None if not found
    """
    url = f"https://{tfe_hostname}/api/registry/v1/modules/{org_name}/{module_name}/{provider_name}/"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/vnd.api+json"
    }

    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()

        data = response.json()
        versions = data.get("versions", [])

        if not versions:
            print("0.1.0")
            sys.exit(0)

        sorted_versions = sorted(
            versions,
            key=lambda v: version.parse(v),
            reverse=True
        )
        return sorted_versions[0]

    except requests.Timeout:
        print("ERROR: Request timed out while fetching module versions", file=sys.stderr)
        sys.exit(1)
    except requests.HTTPError as e:
        if e.response.status_code == 404:
            print("0.1.0")
            sys.exit(0)
        print(f"ERROR: HTTP {e.response.status_code}: {e.response.text}", file=sys.stderr)
        sys.exit(1)
    except requests.RequestException as e:
        print(f"ERROR: Failed to fetch module versions: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


def increment_version(current_version: str, release_type: str) -> str:
    """Increment version number based on semantic versioning rules."""
    try:
        major, minor, patch = map(int, current_version.split('.'))
    except (ValueError, AttributeError):
        raise ValueError(f"Invalid version format: {current_version}")

    release_type = release_type.lower().strip()

    if release_type == "major":
        major += 1
        minor = 0
        patch = 0
    elif release_type == "minor":
        minor += 1
        patch = 0
    elif release_type == "patch":
        patch += 1
    else:
        raise ValueError(
            f"Invalid release type: '{release_type}'. "
            "Must be one of: major, minor, patch"
        )

    return f"{major}.{minor}.{patch}"


def main() -> None:
    """Main entry point."""
    tfe_hostname = os.getenv('TFE_HOSTNAME')
    org_name = os.getenv('TFE_ORG')
    module_name = os.getenv('TFE_MODULE')
    provider_name = os.getenv('TFE_PROVIDER')
    token = os.getenv('TFE_TOKEN')
    release_type = os.getenv('RELEASE_TYPE')

    missing_vars = []
    for var_name, var_val in [
        ('TFE_HOSTNAME', tfe_hostname), ('TFE_ORG', org_name),
        ('TFE_MODULE', module_name), ('TFE_PROVIDER', provider_name),
        ('TFE_TOKEN', token), ('RELEASE_TYPE', release_type),
    ]:
        if not var_val:
            missing_vars.append(var_name)

    if missing_vars:
        print(
            f"ERROR: Required environment variables not set: {', '.join(missing_vars)}",
            file=sys.stderr
        )
        sys.exit(1)

    try:
        current_version = get_latest_version(
            tfe_hostname, org_name, module_name, provider_name, token
        )

        if current_version:
            new_version = increment_version(current_version, release_type)
            print(new_version)
            sys.exit(0)

    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
