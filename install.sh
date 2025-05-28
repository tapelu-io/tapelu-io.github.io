#!/bin/bash
# Installer for Wine Runner Suite (from debivi project)
#
# This script downloads and installs the latest .deb package of Wine Runner Suite.
#
# Usage on target machine:
# curl -sSL https://tapelu-io.github.io/install.sh | sudo bash
#
# To install a specific version (tag from tapelu-io/debivi releases):
# curl -sSL https://tapelu-io.github.io/install.sh | sudo bash -s -- --version v1.1.5

set -e # Exit immediately on error
set -u # Treat unset variables as an error
set -o pipefail # Consider pipeline failures as errors

# --- Configuration ---
DEB_RELEASES_GITHUB_USER="tapelu-io"
DEB_RELEASES_GITHUB_REPO="debivi"   # Repository where .deb RELEASES are hosted

PACKAGE_NAME_IN_DEB="wine-runner-suite"       # The 'Package:' name defined in your DEBIAN/control file
PACKAGE_DEB_FILENAME_BASE="wine-runner-suite" # The base filename of the .deb
ARCH="amd64"

# URL to the file containing the latest version tag (e.g., v1.2.3)
LATEST_VERSION_FILE_URL="https://tapelu-io.github.io/LATEST_WRS_VERSION"
# --- End Configuration ---

_say() { echo "WRS Installer: $1"; }
_say_warn() { echo "WRS Installer WARNING: $1"; }
_say_err() { echo "WRS Installer ERROR: $1" >&2; exit 1; }
_need_cmd() { if ! command -v "$1" > /dev/null 2>&1; then _say_err "Command '$1' is required but not found. Please install it."; fi; }

_check_distro() {
    if ! command -v dpkg >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
        _say_err "This installer is designed for Debian-based systems (e.g., Ubuntu, Mint) that use 'apt' and 'dpkg'."
    fi
}

_say "Starting Wine Runner Suite installation..."

REQUESTED_VERSION_TAG=""

# Simple argument parsing for --version
while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            shift; if [ $# -gt 0 ] && [[ "$1" != "--"* ]]; then REQUESTED_VERSION_TAG="$1"; shift;
            else _say_err "--version flag requires a version argument (e.g., v1.1.5)"; fi;;
        *) _say_warn "Ignoring unknown argument '$1'"; shift;;
    esac
done

# Check prerequisites
_need_cmd "curl"; _need_cmd "apt-get"; _need_cmd "dpkg"; _need_cmd "grep";
_need_cmd "mktemp"; _need_cmd "tr";
_check_distro

if [ "$(id -u)" -ne 0 ]; then
    if [ -z "${SUDO_USER:-}" ]; then
        if [ -t 0 ]; then 
             _say_err "This script must be run with sudo. Please try: sudo bash $0 $*"
        else 
             _say_err "This script must be run with sudo (e.g. curl ... | sudo bash)."
        fi
    fi
fi


TARGET_VERSION_TAG=""
if [ -n "$REQUESTED_VERSION_TAG" ]; then
    TARGET_VERSION_TAG="$REQUESTED_VERSION_TAG"
    _say "Using user-specified version tag: $TARGET_VERSION_TAG"
else
    _say "Determining latest Wine Runner Suite version from $LATEST_VERSION_FILE_URL..."
    LATEST_TAG_FROM_FILE=$(curl -sSL --fail "$LATEST_VERSION_FILE_URL" 2>/dev/null | tr -d '[:space:]')
    if [ $? -ne 0 ] || [ -z "$LATEST_TAG_FROM_FILE" ] || [[ "$LATEST_TAG_FROM_FILE" != v* ]]; then
        _say_err "Could not fetch or validate latest version from '$LATEST_VERSION_FILE_URL'.
    Content received: '${LATEST_TAG_FROM_FILE:-[empty or curl error]}'
    Please ensure:
      1. The URL '$LATEST_VERSION_FILE_URL' is accessible (try opening in a browser).
      2. The file at this URL contains a valid tag (e.g., v1.2.3).
      3. Check GitHub Pages status or your internet connection if issues persist."
    fi
    TARGET_VERSION_TAG="$LATEST_TAG_FROM_FILE"
    _say "Latest version tag found: $TARGET_VERSION_TAG"
fi

if ! [[ "$TARGET_VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.a-zA-Z0-9]+)?$ ]]; then
    _say_err "Invalid version tag format '$TARGET_VERSION_TAG'. Expected format like 'v1.2.3' or 'v1.2.3-rc1'."
fi

VERSION_IN_FILENAME="${TARGET_VERSION_TAG#v}" 
DEB_FILENAME="${PACKAGE_DEB_FILENAME_BASE}_${VERSION_IN_FILENAME}_${ARCH}.deb"
DEB_URL="https://github.com/${DEB_RELEASES_GITHUB_USER}/${DEB_RELEASES_GITHUB_REPO}/releases/download/${TARGET_VERSION_TAG}/${DEB_FILENAME}"

_say "Package version to install: $VERSION_IN_FILENAME (Tag: $TARGET_VERSION_TAG)"

TMP_DIR=$(mktemp -d -t wrs-installer-XXXXXX)
trap '_say "Cleaning up temporary directory $TMP_DIR..."; rm -rf "$TMP_DIR"' EXIT INT TERM
TMP_DEB_PATH="${TMP_DIR}/${DEB_FILENAME}"

_say "Attempting to download .deb package from: $DEB_URL"
if ! curl --progress-bar -fSL -o "$TMP_DEB_PATH" "$DEB_URL"; then
    _say_err "Failed to download '$DEB_FILENAME' from '$DEB_URL'.
Check: 1. Tag '$TARGET_VERSION_TAG' exists as a release in '${DEB_RELEASES_GITHUB_USER}/${DEB_RELEASES_GITHUB_REPO}'.
       2. Asset '$DEB_FILENAME' is attached to that release."
fi
_say ".deb package downloaded to '$TMP_DEB_PATH'"

INSTALLED_VERSION=""
if dpkg -s "$PACKAGE_NAME_IN_DEB" >/dev/null 2>&1; then
    INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' "$PACKAGE_NAME_IN_DEB" 2>/dev/null || echo "query_failed")
    _say "Currently installed version of '$PACKAGE_NAME_IN_DEB': $INSTALLED_VERSION"
    if [ "$INSTALLED_VERSION" != "query_failed" ] && dpkg --compare-versions "$VERSION_IN_FILENAME" "le" "$INSTALLED_VERSION"; then
        _say "Wine Runner Suite version ${VERSION_IN_FILENAME} or newer ($INSTALLED_VERSION) is already installed."
        REINSTALL_CHOICE="N"; if [ -t 0 ]; then read -r -p "Reinstall this version? (y/N): " REINSTALL_CHOICE; fi
        if [[ ! "$REINSTALL_CHOICE" =~ ^([yY][eE][sS]|[yY])$ ]]; then _say "Installation aborted."; exit 0; fi
        _say "Proceeding with reinstallation..."
    elif [ "$INSTALLED_VERSION" != "query_failed" ] && dpkg --compare-versions "$VERSION_IN_FILENAME" "lt" "$INSTALLED_VERSION"; then
         _say "An older version ($VERSION_IN_FILENAME) is requested than installed ($INSTALLED_VERSION)."
        DOWNGRADE_CHOICE="N"; if [ -t 0 ]; then read -r -p "Downgrade to $VERSION_IN_FILENAME? (y/N): " DOWNGRADE_CHOICE; fi
        if [[ ! "$DOWNGRADE_CHOICE" =~ ^([yY][eE][sS]|[yY])$ ]]; then _say "Downgrade aborted."; exit 0; fi
        _say "Proceeding with downgrade..."
    else _say "Preparing to install/upgrade to $VERSION_IN_FILENAME..."; fi
fi

_say "Updating package lists (apt update)..."
apt-get update -qq || _say_warn "apt-get update failed before install, attempting to continue..."

_say "Installing/Upgrading '$PACKAGE_NAME_IN_DEB' using apt..."
if apt-get install -y --allow-downgrades "$TMP_DEB_PATH"; then
    NEW_INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' "$PACKAGE_NAME_IN_DEB" 2>/dev/null || echo "verification_failed")
    if [ "$NEW_INSTALLED_VERSION" = "verification_failed" ]; then
        _say_warn "Installation command finished, but could not verify the installed version of '$PACKAGE_NAME_IN_DEB'."
    else
        _say "Wine Runner Suite version $NEW_INSTALLED_VERSION installed successfully!"
    fi
    _say "Use 'wine-runner' command or double-click .exe/.msi files."
else
    _say_err "Failed to install '$DEB_FILENAME' using apt. Check apt output above.
    You might need to resolve dependencies manually or check system compatibility."
fi

_say "Installation script finished successfully."
exit 0
