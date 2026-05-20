#!/bin/bash

# Verifies that state written by the current SDK can be read by an older SDK.
# Usage: DOWNGRADE_REF=<downgrade-ref> ./scripts/test-downgrade-compatibility.sh
# Historical validation: WRITE_REF=3.48.1 DOWNGRADE_REF=3.48.0 ./scripts/test-downgrade-compatibility.sh

set -euo pipefail

DOWNGRADE_REF="${1:-${DOWNGRADE_REF:-3.48.0}}"
WRITE_REF="${WRITE_REF:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/posthog-ios-downgrade-compat.XXXXXX")"

cleanup() {
    if [ "${KEEP_DOWNGRADE_COMPAT_TMP:-}" = "1" ]; then
        echo "Keeping temp directory: $TMP_DIR"
    else
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

STATE_HOME="$TMP_DIR/home"
CURRENT_SMOKE_DIR="$TMP_DIR/current-smoke"
DOWNGRADED_SMOKE_DIR="$TMP_DIR/downgraded-smoke"
WRITER_REPO_DIR="$TMP_DIR/writer/posthog-ios"
OLD_REPO_DIR="$TMP_DIR/downgraded/posthog-ios"
TOKEN="downgrade_compatibility_project"

mkdir -p "$STATE_HOME/Library/Application Support"

validate_ref() {
    local ref="$1"
    local label="$2"

    # Keep ref inputs safe for git refspecs/options. CI passes static matrix values,
    # but this script is also useful locally via DOWNGRADE_REF/WRITE_REF.
    if [[ -z "$ref" || "$ref" == -* || "$ref" == *..* || ! "$ref" =~ ^[A-Za-z0-9._/+%-]+$ ]]; then
        echo "Invalid $label: $ref" >&2
        exit 64
    fi
}

validate_ref "$DOWNGRADE_REF" "downgrade ref"
if [ -n "$WRITE_REF" ]; then
    validate_ref "$WRITE_REF" "writer ref"
fi

ensure_ref() {
    local ref="$1"
    if ! git -C "$REPO_ROOT" rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
        echo "Fetching refs so '$ref' can be resolved..."
        git -C "$REPO_ROOT" fetch --depth=1 origin "refs/tags/$ref:refs/tags/$ref" \
            || git -C "$REPO_ROOT" fetch --depth=1 origin "$ref" \
            || git -C "$REPO_ROOT" fetch --tags origin
    fi
}

ensure_ref "$DOWNGRADE_REF"
if [ -n "$WRITE_REF" ]; then
    ensure_ref "$WRITE_REF"
fi

create_smoke_package() {
    local package_dir="$1"
    local dependency_path="$2"
    local config_initializer_label="$3"
    local escaped_dependency_path="${dependency_path//\\/\\\\}"
    escaped_dependency_path="${escaped_dependency_path//\"/\\\"}"
    local package_identity
    package_identity="$(basename "$dependency_path")"
    package_identity="${package_identity%.git}"
    package_identity="$(printf '%s' "$package_identity" | tr '[:upper:]' '[:lower:]')"

    mkdir -p "$package_dir/Sources/DowngradeCompatibilitySmoke"

    cat > "$package_dir/Package.swift" <<EOF
// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "DowngradeCompatibilitySmoke",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "DowngradeCompatibilitySmoke", targets: ["DowngradeCompatibilitySmoke"]),
    ],
    dependencies: [
        .package(path: "$escaped_dependency_path"),
    ],
    targets: [
        .target(
            name: "DowngradeCompatibilitySmoke",
            dependencies: [.product(name: "PostHog", package: "$package_identity")]
        ),
    ]
)
EOF

    cat > "$package_dir/Sources/DowngradeCompatibilitySmoke/main.swift" <<'EOF'
import Foundation
import PostHog

let mode = CommandLine.arguments.dropFirst().first ?? "read"
let token = ProcessInfo.processInfo.environment["POSTHOG_DOWNGRADE_TEST_TOKEN"] ?? "downgrade_compatibility_project"

let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
print("Application Support: \(appSupport.path)")

let config = PostHogConfig(__CONFIG_INITIALIZER_LABEL__: token, host: "http://127.0.0.1:9")
config.flushAt = 10_000
config.maxQueueSize = 10_000
config.preloadFeatureFlags = false
config.captureApplicationLifecycleEvents = false
config.captureScreenViews = false
config.enableSwizzling = false

PostHogSDK.shared.setup(config)

switch mode {
case "write":
    PostHogSDK.shared.identify(
        "downgrade-compatibility-user",
        userProperties: ["source": "downgrade-compatibility"]
    )
    PostHogSDK.shared.group(
        type: "organization",
        key: "posthog",
        groupProperties: ["ci": true]
    )

    for index in 0 ..< 5 {
        PostHogSDK.shared.capture(
            "downgrade compatibility event",
            properties: ["index": index, "source": "current-sdk"]
        )
    }

    print("Wrote current SDK state for token \(token)")
case "read":
    PostHogSDK.shared.capture(
        "downgrade compatibility read smoke",
        properties: ["source": "downgraded-sdk"]
    )
    print("Downgraded SDK started and read latest state for token \(token)")
default:
    fatalError("Unknown mode: \(mode)")
}

// Give any setup-time async work a short chance to start so startup crashes are observable.
Thread.sleep(forTimeInterval: 0.2)
EOF

    perl -pi -e "s/__CONFIG_INITIALIZER_LABEL__/$config_initializer_label/g" \
        "$package_dir/Sources/DowngradeCompatibilitySmoke/main.swift"

    local dependency_resolved="$dependency_path/Package.resolved"
    if [ -f "$dependency_resolved" ]; then
        cp "$dependency_resolved" "$package_dir/Package.resolved"
    fi
}

run_smoke() {
    local package_dir="$1"
    local mode="$2"

    # CFFIXED_USER_HOME makes Foundation's user-domain Application Support
    # directory point at our temp home on macOS, keeping the smoke state isolated.
    CFFIXED_USER_HOME="$STATE_HOME" \
    HOME="$STATE_HOME" \
    POSTHOG_DOWNGRADE_TEST_TOKEN="$TOKEN" \
    xcrun swift run --package-path "$package_dir" DowngradeCompatibilitySmoke "$mode"
}

count_queue_files() {
    local state_root="$STATE_HOME/Library/Application Support"
    if [ ! -d "$state_root" ]; then
        echo 0
        return
    fi

    find "$state_root" -type f \
        \( -path "*/posthog.queueFolder/*" -o -path "*/posthog.queueFolder.uuid/*" \) \
        | wc -l | tr -d ' '
}

if [ -n "$WRITE_REF" ]; then
    echo "Checking out writer SDK ref $WRITE_REF"
    mkdir -p "$(dirname "$WRITER_REPO_DIR")"
    git clone --quiet --shared "$REPO_ROOT" "$WRITER_REPO_DIR"
    git -C "$WRITER_REPO_DIR" checkout --quiet "$WRITE_REF"
    WRITER_DEPENDENCY_PATH="$WRITER_REPO_DIR"
    WRITER_CONFIG_LABEL="apiKey"
    WRITER_DESCRIPTION="$WRITE_REF"
else
    WRITER_DEPENDENCY_PATH="$REPO_ROOT"
    WRITER_CONFIG_LABEL="projectToken"
    WRITER_DESCRIPTION="current checkout at $REPO_ROOT"
fi

echo "Writing state with $WRITER_DESCRIPTION"
create_smoke_package "$CURRENT_SMOKE_DIR" "$WRITER_DEPENDENCY_PATH" "$WRITER_CONFIG_LABEL"
run_smoke "$CURRENT_SMOKE_DIR" write

QUEUE_FILE_COUNT="$(count_queue_files)"
if [ "$QUEUE_FILE_COUNT" -eq 0 ]; then
    echo "Expected the current SDK to write queued event files, but none were found. State tree:" >&2
    find "$STATE_HOME/Library/Application Support" -maxdepth 8 -print | sort >&2 || true
    exit 1
fi

echo "Current SDK wrote $QUEUE_FILE_COUNT queue file(s)."

echo "Checking out downgraded SDK ref $DOWNGRADE_REF"
mkdir -p "$(dirname "$OLD_REPO_DIR")"
git clone --quiet --shared "$REPO_ROOT" "$OLD_REPO_DIR"
git -C "$OLD_REPO_DIR" checkout --quiet "$DOWNGRADE_REF"

create_smoke_package "$DOWNGRADED_SMOKE_DIR" "$OLD_REPO_DIR" "apiKey"
echo "Starting downgraded SDK ($DOWNGRADE_REF) against current SDK state"
run_smoke "$DOWNGRADED_SMOKE_DIR" read

echo "Downgrade compatibility smoke test passed for $DOWNGRADE_REF"
