#!/usr/bin/env bash
# update.sh - Check for new VS Code versions and optionally update hashes
# Usage: ./update.sh          - Check if update needed
#        ./update.sh --update - Fetch hashes and update version.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/version.json"

# Platform mappings: nix system -> VS Code download platform
declare -A PLATFORM_MAP=(
  ["x86_64-linux"]="linux-x64"
  ["aarch64-linux"]="linux-arm64"
  ["x86_64-darwin"]="darwin"
  ["aarch64-darwin"]="darwin-arm64"
)

# Get current version from version.json
get_current_version() {
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "Error: version.json not found at $VERSION_FILE" >&2
    exit 1
  fi
  jq -r '.version' "$VERSION_FILE"
}

# Get latest VS Code version from GitHub API
# Uses /releases endpoint to find newest non-prerelease, non-draft release
# (doesn't rely on Microsoft marking a release as "latest")
get_latest_version() {
  local tag_name
  # Get all releases, filter to non-prerelease/non-draft, take first (most recent)
  tag_name=$(curl -s "https://api.github.com/repos/microsoft/vscode/releases" | \
    jq -r '[.[] | select(.prerelease == false and .draft == false)][0].tag_name')

  if [[ -z "$tag_name" || "$tag_name" == "null" ]]; then
    echo "Error: Could not get latest version from GitHub API" >&2
    exit 1
  fi

  # Strip leading 'v' if present
  echo "${tag_name#v}"
}

# Compare versions (returns 0 if v1 < v2, 1 otherwise)
version_lt() {
  local v1="$1"
  local v2="$2"

  # If versions are equal, v1 is not less than v2
  if [[ "$v1" == "$v2" ]]; then
    return 1
  fi

  # Use sort -V for version comparison
  local sorted
  sorted=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)

  if [[ "$sorted" == "$v1" ]]; then
    return 0  # v1 < v2
  else
    return 1  # v1 >= v2
  fi
}

# Get download URL for a platform
get_download_url() {
  local version="$1"
  local platform="$2"
  echo "https://update.code.visualstudio.com/${version}/${platform}/stable"
}

# Fetch hash for a platform using nix-prefetch-url
fetch_hash() {
  local version="$1"
  local nix_platform="$2"
  local vscode_platform="${PLATFORM_MAP[$nix_platform]}"
  local url

  url=$(get_download_url "$version" "$vscode_platform")
  echo "Fetching hash for $nix_platform ($vscode_platform)..." >&2

  # Use nix-prefetch-url to download and hash
  local base32_hash
  base32_hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)

  if [[ -z "$base32_hash" ]]; then
    echo "Error: Failed to fetch hash for $nix_platform" >&2
    return 1
  fi

  # Convert to SRI format
  local sri_hash
  sri_hash=$(nix-hash --type sha256 --to-sri "$base32_hash")

  echo "$sri_hash"
}

# Fetch all hashes and update version.json
update_version_json() {
  local new_version="$1"

  echo "Fetching hashes for VS Code $new_version..." >&2

  local hash_x86_64_linux hash_aarch64_linux hash_x86_64_darwin hash_aarch64_darwin

  hash_x86_64_linux=$(fetch_hash "$new_version" "x86_64-linux")
  hash_aarch64_linux=$(fetch_hash "$new_version" "aarch64-linux")
  hash_x86_64_darwin=$(fetch_hash "$new_version" "x86_64-darwin")
  hash_aarch64_darwin=$(fetch_hash "$new_version" "aarch64-darwin")

  # Create new version.json
  cat > "$VERSION_FILE" << EOF
{
  "version": "$new_version",
  "hashes": {
    "x86_64-linux": "$hash_x86_64_linux",
    "aarch64-linux": "$hash_aarch64_linux",
    "x86_64-darwin": "$hash_x86_64_darwin",
    "aarch64-darwin": "$hash_aarch64_darwin"
  }
}
EOF

  echo "Updated version.json to version $new_version" >&2
}

main() {
  local do_update=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --update)
        do_update=true
        shift
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--update]" >&2
        exit 1
        ;;
    esac
  done

  local current_version
  local latest_version

  current_version=$(get_current_version)
  latest_version=$(get_latest_version)

  echo "Current version: $current_version" >&2
  echo "Latest version: $latest_version" >&2

  if version_lt "$current_version" "$latest_version"; then
    echo "UPDATE_NEEDED=true"
    echo "NEW_VERSION=$latest_version"

    if $do_update; then
      update_version_json "$latest_version"
    fi
  else
    echo "UPDATE_NEEDED=false"
  fi
}

main "$@"
