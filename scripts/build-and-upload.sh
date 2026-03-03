#!/bin/bash

# Builds PostHogExample with dSYM symbols, uploads them to PostHog, and launches the app.
#
# Usage:
#   ./scripts/build-and-upload.sh [--host HOST] [--api-key KEY] [--project-id ID] [--simulator UDID]
#
# Environment variables (used as fallback):
#   POSTHOG_HOST         - PostHog host (default: http://localhost:8010)
#   POSTHOG_CLI_API_KEY  - Personal API key
#   POSTHOG_CLI_PROJECT_ID - Project ID (default: 1)
#   SIMULATOR_UDID       - Simulator UDID (default: first available booted or iPhone simulator)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
PROJECT="$PROJECT_ROOT/PostHog.xcodeproj"
SCHEME="PostHogExample"
BUNDLE_ID="com.posthog.PostHogExample"
DSYM_DIR="$PROJECT_ROOT/build/dSYMs"

# Defaults
HOST="${POSTHOG_HOST:-http://localhost:8010}"
API_KEY="${POSTHOG_CLI_API_KEY:-}"
PROJECT_ID="${POSTHOG_CLI_PROJECT_ID:-1}"
SIMULATOR="${SIMULATOR_UDID:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host) HOST="$2"; shift 2 ;;
        --api-key) API_KEY="$2"; shift 2 ;;
        --project-id) PROJECT_ID="$2"; shift 2 ;;
        --simulator) SIMULATOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$API_KEY" ]; then
    echo "Error: API key required. Set POSTHOG_CLI_API_KEY or pass --api-key."
    exit 1
fi

# Find simulator if not specified
if [ -z "$SIMULATOR" ]; then
    # Try to find a booted simulator first
    SIMULATOR=$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['state'] == 'Booted' and 'iPhone' in d['name']:
            print(d['udid']); sys.exit(0)
" 2>/dev/null || true)

    # Fall back to first available iPhone simulator
    if [ -z "$SIMULATOR" ]; then
        SIMULATOR=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    if 'iOS' not in runtime: continue
    for d in devices:
        if 'iPhone' in d['name']:
            print(d['udid']); sys.exit(0)
" 2>/dev/null || true)
    fi

    if [ -z "$SIMULATOR" ]; then
        echo "Error: No iPhone simulator found."
        exit 1
    fi
fi

echo "==> Configuration"
echo "    Host:      $HOST"
echo "    Project:   $PROJECT_ID"
echo "    Simulator: $SIMULATOR"
echo ""

# Boot simulator if needed
SIM_STATE=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['udid'] == '$SIMULATOR':
            print(d['state']); sys.exit(0)
")
if [ "$SIM_STATE" != "Booted" ]; then
    echo "==> Booting simulator..."
    xcrun simctl boot "$SIMULATOR"
    open -a Simulator
fi

# Build
echo "==> Building $SCHEME with dSYM symbols..."
set -o pipefail
xcrun xcodebuild clean build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIMULATOR" \
    -configuration Debug \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    DWARF_DSYM_FOLDER_PATH="$DSYM_DIR" \
    ENABLE_DEBUG_DYLIB=NO \
    2>&1 | tail -3 || { echo "Build failed"; exit 1; }
echo "    Build succeeded."

# Fix rpath — xcodebuild sets an absolute DerivedData rpath for SPM packages
# which doesn't resolve after simctl install. Add the standard embedded frameworks rpath.
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Debug-iphonesimulator/$SCHEME.app/$SCHEME" -newer "$DSYM_DIR" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app binary."
    exit 1
fi
APP_BUNDLE=$(dirname "$APP_PATH")

echo "==> Fixing rpath for simulator install..."
install_name_tool -add_rpath @executable_path/Frameworks "$APP_PATH" 2>/dev/null || true
codesign --force --sign - "$APP_PATH"
codesign --force --sign - "$APP_BUNDLE"

# Upload dSYMs
echo "==> Uploading dSYMs to $HOST..."
POSTHOG_CLI_API_KEY="$API_KEY" POSTHOG_CLI_PROJECT_ID="$PROJECT_ID" \
    posthog-cli --host "$HOST" exp dsym upload \
    --directory "$DSYM_DIR" \
    --main-dsym "$SCHEME.app.dSYM" \
    --include-source

# Install and launch
echo "==> Installing and launching on simulator..."
xcrun simctl terminate "$SIMULATOR" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$SIMULATOR" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIMULATOR" "$APP_BUNDLE"
xcrun simctl launch "$SIMULATOR" "$BUNDLE_ID"

echo ""
echo "==> Done! $SCHEME is running on simulator $SIMULATOR."
