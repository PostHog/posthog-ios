#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPLOAD_SCRIPT="${ROOT_DIR}/build-tools/upload-symbols.sh"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
    echo "error: $*" >&2
    exit 1
}

assert_file_contains_line() {
    local file="$1"
    local expected="$2"
    grep -Fxq -- "$expected" "$file" || fail "Expected '$expected' in $file"
}

create_fixture() {
    local name="$1"
    FIXTURE_DIR="${TEMP_DIR}/${name}"
    HOME_DIR="${FIXTURE_DIR}/home"
    FAKE_BIN="${FIXTURE_DIR}/bin"
    SRC_ROOT="${FIXTURE_DIR}/source"
    DSYM_FOLDER="${FIXTURE_DIR}/dSYMs"
    DSYM_NAME="ExampleApp.app.dSYM"
    EXECUTABLE_NAME="ExampleApp"
    MAIN_DWARF="${DSYM_FOLDER}/${DSYM_NAME}/Contents/Resources/DWARF/${EXECUTABLE_NAME}"
    TARGET_BUILD_DIR="${FIXTURE_DIR}/build"
    EXECUTABLE_PATH="ExampleApp.app/ExampleApp"
    APP_EXECUTABLE="${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}"
    CLI_ARGS_FILE="${FIXTURE_DIR}/cli-args"
    DWARFDUMP_ATTEMPTS="${FIXTURE_DIR}/dwarfdump-attempts"

    mkdir -p "$HOME_DIR/.posthog" "$FAKE_BIN" "$SRC_ROOT/Config" "$(dirname "$MAIN_DWARF")" "$(dirname "$APP_EXECUTABLE")"
    printf 'dwarf' > "$MAIN_DWARF"
    printf 'executable' > "$APP_EXECUTABLE"

    cat > "$HOME_DIR/.posthog/posthog-cli" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
    echo "posthog-cli 0.10.0"
    exit 0
fi
printf '%s\n' "$@" > "$TEST_CLI_ARGS_FILE"
EOF
    chmod +x "$HOME_DIR/.posthog/posthog-cli"

    cat > "$FAKE_BIN/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$FAKE_BIN/sleep"
}

write_plist() {
    local path="$1"
    local release_version="$2"
    local build_version="$3"
    cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>${release_version}</string>
    <key>CFBundleVersion</key>
    <string>${build_version}</string>
</dict>
</plist>
EOF
}

run_upload() {
    set +e
    OUTPUT=$(env \
        HOME="$HOME_DIR" \
        PATH="$FAKE_BIN:$PATH" \
        CONFIGURATION="${TEST_CONFIGURATION:-Release}" \
        DEBUG_INFORMATION_FORMAT="${TEST_DEBUG_INFORMATION_FORMAT:-dwarf-with-dsym}" \
        DWARF_DSYM_FOLDER_PATH="$DSYM_FOLDER" \
        DWARF_DSYM_FILE_NAME="$DSYM_NAME" \
        EXECUTABLE_NAME="$EXECUTABLE_NAME" \
        TARGET_BUILD_DIR="$TARGET_BUILD_DIR" \
        EXECUTABLE_PATH="$EXECUTABLE_PATH" \
        SRCROOT="$SRC_ROOT" \
        INFOPLIST_FILE="$TEST_INFOPLIST_FILE" \
        PRODUCT_BUNDLE_IDENTIFIER="com.example.app" \
        MARKETING_VERSION="1.0" \
        CURRENT_PROJECT_VERSION="1" \
        TEST_CLI_ARGS_FILE="$CLI_ARGS_FILE" \
        TEST_DWARFDUMP_ATTEMPTS="$DWARFDUMP_ATTEMPTS" \
        bash "$UPLOAD_SCRIPT" 2>&1)
    STATUS=$?
    set -e
}

test_waits_for_current_dsym_and_uses_source_plist_versions() {
    create_fixture "ready"
    write_plist "$SRC_ROOT/Config/Info.plist" "2.10.0" "154"
    TEST_INFOPLIST_FILE="Config/Info.plist"

    cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/bin/sh
case "$3" in
    *.dSYM/*)
        attempts=$(cat "$TEST_DWARFDUMP_ATTEMPTS" 2>/dev/null || printf 0)
        attempts=$((attempts + 1))
        printf '%s' "$attempts" > "$TEST_DWARFDUMP_ATTEMPTS"
        if [ "$attempts" -lt 3 ]; then
            printf 'UUID: OLD-UUID (arm64) %s\n' "$3"
        else
            printf 'UUID: CURRENT-UUID (arm64) %s\n' "$3"
        fi
        ;;
    *) printf 'UUID: CURRENT-UUID (arm64) %s\n' "$3" ;;
esac
EOF
    chmod +x "$FAKE_BIN/xcrun"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected upload to succeed, got status $STATUS: $OUTPUT"
    [ "$(cat "$DWARFDUMP_ATTEMPTS")" = "3" ] || fail "Expected three dSYM readiness attempts"
    [ -f "$CLI_ARGS_FILE" ] || fail "Expected posthog-cli to run"
    assert_file_contains_line "$CLI_ARGS_FILE" "--release-version"
    assert_file_contains_line "$CLI_ARGS_FILE" "2.10.0"
    assert_file_contains_line "$CLI_ARGS_FILE" "--build"
    assert_file_contains_line "$CLI_ARGS_FILE" "154"
}

test_skips_upload_when_dsym_never_matches() {
    create_fixture "not-ready"
    write_plist "$SRC_ROOT/Config/Info.plist" "2.10.0" "154"
    TEST_INFOPLIST_FILE="Config/Info.plist"

    cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/bin/sh
case "$3" in
    *.dSYM/*) printf 'UUID: OLD-UUID (arm64) %s\n' "$3" ;;
    *) printf 'UUID: CURRENT-UUID (arm64) %s\n' "$3" ;;
esac
EOF
    chmod +x "$FAKE_BIN/xcrun"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected an unavailable dSYM to skip without failing the build"
    [[ "$OUTPUT" == *"skipping upload"* ]] || fail "Expected a warning when the dSYM stays unavailable"
    [ ! -f "$CLI_ARGS_FILE" ] || fail "posthog-cli must not run with a stale dSYM"
}

test_falls_back_for_unresolved_source_plist_versions() {
    create_fixture "fallback"
    write_plist "$SRC_ROOT/Config/Info.plist" "\${MARKETING_VERSION}" "\$(CURRENT_PROJECT_VERSION)"
    TEST_INFOPLIST_FILE="$SRC_ROOT/Config/Info.plist"
    TEST_DEBUG_INFORMATION_FORMAT="dwarf"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected upload with fallback versions to succeed: $OUTPUT"
    assert_file_contains_line "$CLI_ARGS_FILE" "--release-version"
    assert_file_contains_line "$CLI_ARGS_FILE" "1.0"
    assert_file_contains_line "$CLI_ARGS_FILE" "--build"
    assert_file_contains_line "$CLI_ARGS_FILE" "1"
}

bash -n "$UPLOAD_SCRIPT"
test_waits_for_current_dsym_and_uses_source_plist_versions
test_skips_upload_when_dsym_never_matches
test_falls_back_for_unresolved_source_plist_versions

echo "upload-symbols tests passed"
