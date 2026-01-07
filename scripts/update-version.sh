#!/usr/bin/env bash
#
# Update taws to the latest version from GitHub releases.
# This script is called by GitHub Actions hourly and can also be run manually.
#
# Usage:
#   ./scripts/update-version.sh              # Update to latest version
#   ./scripts/update-version.sh --check      # Check for updates only
#   ./scripts/update-version.sh --version X  # Update to specific version

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly GITHUB_API_URL="https://api.github.com"
readonly REPO_OWNER="huseyinbabal"
readonly REPO_NAME="taws"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_current_version() {
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1 || echo "unknown"
}

get_latest_version_from_github() {
    local response
    response=$(curl -s "${GITHUB_API_URL}/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest")
    
    # Extract tag_name and remove 'v' prefix if present
    echo "$response" | sed -n 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/p' | head -1
}

fetch_source_hash() {
    local version="$1"
    log_info "Fetching source hash for version $version..."
    
    # Use nix-prefetch-github to get the hash
    local result
    if command -v nix-prefetch-github >/dev/null 2>&1; then
        result=$(nix-prefetch-github "$REPO_OWNER" "$REPO_NAME" --rev "v$version" 2>/dev/null)
    else
        # Fall back to nix shell
        result=$(nix shell nixpkgs#nix-prefetch-github -c nix-prefetch-github "$REPO_OWNER" "$REPO_NAME" --rev "v$version" 2>/dev/null)
    fi
    
    # Extract hash from JSON output
    echo "$result" | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p' | head -1
}

fetch_cargo_hash() {
    local version="$1"
    local src_hash="$2"
    
    log_info "Building to determine cargoHash (this may take a while)..."
    
    # Create a temporary file with the updated package
    local temp_package
    temp_package=$(mktemp)
    
    # Update the source hash in package.nix temporarily
    sed "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" package.nix > "$temp_package"
    
    # Try to build - it will fail but tell us the correct cargoHash
    local build_output
    build_output=$(nix build --impure --expr "
      let
        pkgs = import <nixpkgs> {};
      in pkgs.callPackage $temp_package {}
    " 2>&1 || true)
    
    rm -f "$temp_package"
    
    # Extract the expected hash from the error message
    local cargo_hash
    cargo_hash=$(echo "$build_output" | grep -oP 'got:\s+sha256-[A-Za-z0-9+/=]+' | sed 's/got:\s*//' | head -1)
    
    if [ -z "$cargo_hash" ]; then
        # Try alternative pattern
        cargo_hash=$(echo "$build_output" | grep -oP 'sha256-[A-Za-z0-9+/=]{43,44}' | tail -1)
    fi
    
    echo "$cargo_hash"
}

update_package_version() {
    local version="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/version = \"[^\"]*\"/version = \"$version\"/" package.nix
    else
        sed -i "s/version = \"[^\"]*\"/version = \"$version\"/" package.nix
    fi
}

update_source_hash() {
    local hash="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|hash = \"sha256-[^\"]*\"|hash = \"$hash\"|" package.nix
    else
        sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$hash\"|" package.nix
    fi
}

update_cargo_hash() {
    local hash="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|cargoHash = \"sha256-[^\"]*\"|cargoHash = \"$hash\"|" package.nix
    else
        sed -i "s|cargoHash = \"sha256-[^\"]*\"|cargoHash = \"$hash\"|" package.nix
    fi
}

update_to_version() {
    local new_version="$1"
    
    log_info "Updating to version $new_version..."
    
    # Update version in package.nix
    update_package_version "$new_version"
    
    # Fetch and update source hash
    log_info "Fetching source hash..."
    local src_hash
    src_hash=$(fetch_source_hash "$new_version")
    
    if [ -z "$src_hash" ]; then
        log_error "Failed to fetch source hash"
        return 1
    fi
    
    log_info "Source hash: $src_hash"
    update_source_hash "$src_hash"
    
    # For Rust packages, we need to determine cargoHash
    # This is done by attempting a build and extracting the hash from the error
    log_info "Determining cargoHash (this requires a build attempt)..."
    
    # First, set a dummy cargoHash to trigger the hash mismatch error
    update_cargo_hash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    
    # Try to build and capture the correct hash
    local build_output
    build_output=$(nix build .#taws 2>&1 || true)
    
    # Extract the correct cargoHash from build output
    local cargo_hash
    cargo_hash=$(echo "$build_output" | grep -oE 'got:\s*sha256-[A-Za-z0-9+/=]+' | sed 's/got:\s*//' | head -1)
    
    if [ -z "$cargo_hash" ]; then
        # Try alternative extraction
        cargo_hash=$(echo "$build_output" | grep -oE 'sha256-[A-Za-z0-9+/=]{43,44}' | tail -1)
    fi
    
    if [ -n "$cargo_hash" ]; then
        log_info "cargoHash: $cargo_hash"
        update_cargo_hash "$cargo_hash"
    else
        log_warn "Could not automatically determine cargoHash"
        log_warn "You may need to run 'nix build' and update cargoHash manually"
    fi
    
    # Verify the build
    log_info "Verifying build..."
    if nix build .#taws 2>/dev/null; then
        log_info "Build successful!"
        return 0
    else
        log_error "Build verification failed"
        log_warn "You may need to manually fix the cargoHash"
        return 1
    fi
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "package.nix" ]; then
        log_error "flake.nix or package.nix not found. Please run this script from the repository root."
        exit 1
    fi
}

ensure_required_tools_installed() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
    command -v curl >/dev/null 2>&1 || { log_error "curl is required but not installed."; exit 1; }
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Update taws to the latest version from GitHub releases."
    echo ""
    echo "Options:"
    echo "  --version VERSION  Update to specific version (without 'v' prefix)"
    echo "  --check           Only check for updates, don't apply"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Update to latest version"
    echo "  $0 --check            # Check if update is available"
    echo "  $0 --version 1.1.2    # Update to specific version"
}

update_flake_lock() {
    if command -v nix >/dev/null 2>&1; then
        log_info "Updating flake.lock..."
        nix flake update 2>/dev/null || true
    fi
}

show_changes() {
    echo ""
    log_info "Changes made:"
    git diff --stat package.nix flake.lock 2>/dev/null || true
}

main() {
    ensure_in_repository_root
    ensure_required_tools_installed
    
    local target_version=""
    local check_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --check)
                check_only=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    local current_version
    current_version=$(get_current_version)
    
    local latest_version
    if [ -n "$target_version" ]; then
        latest_version="$target_version"
    else
        latest_version=$(get_latest_version_from_github)
    fi
    
    if [ -z "$latest_version" ]; then
        log_error "Failed to fetch latest version from GitHub"
        exit 1
    fi
    
    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"
    
    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        exit 0
    fi
    
    if [ "$check_only" = true ]; then
        log_info "Update available: $current_version -> $latest_version"
        exit 1  # Exit with non-zero to indicate update is available (for CI)
    fi
    
    if update_to_version "$latest_version"; then
        log_info "Successfully updated taws from $current_version to $latest_version"
        update_flake_lock
        show_changes
    else
        log_error "Update failed"
        exit 1
    fi
}

main "$@"
