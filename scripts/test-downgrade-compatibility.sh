#!/bin/bash

# Verifies that persisted state written by the current SDK does not break an older SDK.
# The current-writer path seeds identity storage plus analytics, replay, and logs queues.
# Usage: DOWNGRADE_REF=<downgrade-ref> ./scripts/test-downgrade-compatibility.sh
# Historical event-queue validation: WRITE_REF=3.48.3 DOWNGRADE_REF=3.48.0 ./scripts/test-downgrade-compatibility.sh

set -euo pipefail

DOWNGRADE_REF="${1:-${DOWNGRADE_REF:-3.48.0}}"
WRITE_REF="${WRITE_REF:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SMOKE_TEMPLATE_DIR="$SCRIPT_DIR/downgrade-compatibility-smoke"
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

    mkdir -p "$package_dir"
    cp -R "$SMOKE_TEMPLATE_DIR/." "$package_dir"

    local dependency_resolved="$dependency_path/Package.resolved"
    if [ -f "$dependency_resolved" ]; then
        cp "$dependency_resolved" "$package_dir/Package.resolved"
    fi
}

run_smoke() {
    local package_dir="$1"
    local mode="$2"
    local dependency_path="$3"
    local include_current_storage_writes="${4:-0}"

    # CFFIXED_USER_HOME makes Foundation's user-domain Application Support
    # directory point at our temp home on macOS, keeping the smoke state isolated.
    CFFIXED_USER_HOME="$STATE_HOME" \
    HOME="$STATE_HOME" \
    POSTHOG_DOWNGRADE_TEST_TOKEN="$TOKEN" \
    POSTHOG_DOWNGRADE_SMOKE_DEPENDENCY_PATH="$dependency_path" \
    POSTHOG_DOWNGRADE_SMOKE_CURRENT_WRITER="$include_current_storage_writes" \
    xcrun swift run --package-path "$package_dir" DowngradeCompatibilitySmoke "$mode"
}

count_storage_files() {
    local folder_name="$1"
    local state_root="$STATE_HOME/Library/Application Support"
    if [ ! -d "$state_root" ]; then
        echo 0
        return
    fi

    find "$state_root" -type f -path "*/$folder_name/*" | wc -l | tr -d ' '
}

count_storage_key_files() {
    local file_name="$1"
    local state_root="$STATE_HOME/Library/Application Support"
    if [ ! -d "$state_root" ]; then
        echo 0
        return
    fi

    find "$state_root" -type f -name "$file_name" | wc -l | tr -d ' '
}

count_event_queue_files() {
    local current_queue_count
    local legacy_queue_count
    current_queue_count="$(count_storage_files "posthog.queueFolder.uuid")"
    legacy_queue_count="$(count_storage_files "posthog.queueFolder")"
    echo $((current_queue_count + legacy_queue_count))
}

count_replay_queue_files() {
    local current_queue_count
    local legacy_queue_count
    current_queue_count="$(count_storage_files "posthog.replayFolder.uuid")"
    legacy_queue_count="$(count_storage_files "posthog.replayFolder")"
    echo $((current_queue_count + legacy_queue_count))
}

require_positive_count() {
    local description="$1"
    local count="$2"
    if [ "$count" -eq 0 ]; then
        echo "Expected $description to be persisted, but none were found. State tree:" >&2
        find "$STATE_HOME/Library/Application Support" -maxdepth 8 -print | sort >&2 || true
        exit 1
    fi
}

if [ -n "$WRITE_REF" ]; then
    echo "Checking out writer SDK ref $WRITE_REF"
    mkdir -p "$(dirname "$WRITER_REPO_DIR")"
    git clone --quiet --shared "$REPO_ROOT" "$WRITER_REPO_DIR"
    git -C "$WRITER_REPO_DIR" checkout --quiet "$WRITE_REF"
    WRITER_DEPENDENCY_PATH="$WRITER_REPO_DIR"
    WRITER_DESCRIPTION="$WRITE_REF"
    INCLUDE_CURRENT_STORAGE_WRITES=0
else
    WRITER_DEPENDENCY_PATH="$REPO_ROOT"
    WRITER_DESCRIPTION="current checkout at $REPO_ROOT"
    INCLUDE_CURRENT_STORAGE_WRITES=1
fi

echo "Writing state with $WRITER_DESCRIPTION"
create_smoke_package "$CURRENT_SMOKE_DIR" "$WRITER_DEPENDENCY_PATH"
run_smoke "$CURRENT_SMOKE_DIR" write "$WRITER_DEPENDENCY_PATH" "$INCLUDE_CURRENT_STORAGE_WRITES"

EVENT_QUEUE_FILE_COUNT="$(count_event_queue_files)"
require_positive_count "queued analytics event files" "$EVENT_QUEUE_FILE_COUNT"
require_positive_count "persisted distinctId" "$(count_storage_key_files "posthog.distinctId")"
require_positive_count "persisted group properties" "$(count_storage_key_files "posthog.groups")"

echo "Writer SDK persisted $EVENT_QUEUE_FILE_COUNT analytics event queue file(s)."

if [ "$INCLUDE_CURRENT_STORAGE_WRITES" = "1" ]; then
    CURRENT_REPLAY_QUEUE_FILE_COUNT="$(count_storage_files "posthog.replayFolder.uuid")"
    LEGACY_REPLAY_QUEUE_FILE_COUNT="$(count_storage_files "posthog.replayFolder")"
    REPLAY_QUEUE_FILE_COUNT="$(count_replay_queue_files)"
    LOGS_QUEUE_FILE_COUNT="$(count_storage_files "posthog.logsFolder")"

    require_positive_count "queued replay snapshot files" "$REPLAY_QUEUE_FILE_COUNT"
    require_positive_count "queued log files" "$LOGS_QUEUE_FILE_COUNT"

    if [ "$LEGACY_REPLAY_QUEUE_FILE_COUNT" -ne 0 ]; then
        echo "Warning: current SDK wrote $LEGACY_REPLAY_QUEUE_FILE_COUNT replay snapshot file(s) to legacy posthog.replayFolder." >&2
    fi

    echo "Current SDK also persisted $REPLAY_QUEUE_FILE_COUNT replay snapshot file(s) ($CURRENT_REPLAY_QUEUE_FILE_COUNT current, $LEGACY_REPLAY_QUEUE_FILE_COUNT legacy) and $LOGS_QUEUE_FILE_COUNT log file(s)."
fi

echo "Checking out downgraded SDK ref $DOWNGRADE_REF"
mkdir -p "$(dirname "$OLD_REPO_DIR")"
git clone --quiet --shared "$REPO_ROOT" "$OLD_REPO_DIR"
git -C "$OLD_REPO_DIR" checkout --quiet "$DOWNGRADE_REF"

create_smoke_package "$DOWNGRADED_SMOKE_DIR" "$OLD_REPO_DIR"
echo "Starting downgraded SDK ($DOWNGRADE_REF) against current SDK state"
run_smoke "$DOWNGRADED_SMOKE_DIR" read "$OLD_REPO_DIR" 0

echo "Downgrade compatibility smoke test passed for $DOWNGRADE_REF"
