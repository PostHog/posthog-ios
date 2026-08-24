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
    LSOF_ATTEMPTS="${FIXTURE_DIR}/lsof-attempts"
    XCRUN_MARKER="${FIXTURE_DIR}/xcrun-ran"
    TEST_CONFIGURATION="Release"
    TEST_DEBUG_INFORMATION_FORMAT="dwarf-with-dsym"
    TEST_DSYM_TIMEOUT="60"
    TEST_APP_VERSION=""
    TEST_BUILD_NUMBER=""
    TEST_INFOPLIST_PREPROCESS="NO"
    TEST_INFOPLIST_PATH=""

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

    cat > "$FAKE_BIN/lsof" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$FAKE_BIN/lsof"

    cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/bin/sh
printf 'UUID: CURRENT-UUID (arm64) %s\n' "$3"
EOF
    chmod +x "$FAKE_BIN/xcrun"
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
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        CONFIGURATION="$TEST_CONFIGURATION" \
        DEBUG_INFORMATION_FORMAT="$TEST_DEBUG_INFORMATION_FORMAT" \
        POSTHOG_DSYM_TIMEOUT="$TEST_DSYM_TIMEOUT" \
        POSTHOG_LSOF_PATH="$FAKE_BIN/lsof" \
        DWARF_DSYM_FOLDER_PATH="$DSYM_FOLDER" \
        DWARF_DSYM_FILE_NAME="$DSYM_NAME" \
        EXECUTABLE_NAME="$EXECUTABLE_NAME" \
        TARGET_BUILD_DIR="$TARGET_BUILD_DIR" \
        EXECUTABLE_PATH="$EXECUTABLE_PATH" \
        SRCROOT="$SRC_ROOT" \
        INFOPLIST_FILE="$TEST_INFOPLIST_FILE" \
        INFOPLIST_PREPROCESS="$TEST_INFOPLIST_PREPROCESS" \
        INFOPLIST_PATH="$TEST_INFOPLIST_PATH" \
        PRODUCT_BUNDLE_IDENTIFIER="com.example.app" \
        MARKETING_VERSION="1.0" \
        CURRENT_PROJECT_VERSION="1" \
        APP_VERSION="$TEST_APP_VERSION" \
        BUILD_NUMBER="$TEST_BUILD_NUMBER" \
        TEST_CLI_ARGS_FILE="$CLI_ARGS_FILE" \
        TEST_DWARFDUMP_ATTEMPTS="$DWARFDUMP_ATTEMPTS" \
        TEST_LSOF_ATTEMPTS="$LSOF_ATTEMPTS" \
        TEST_XCRUN_MARKER="$XCRUN_MARKER" \
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

test_waits_until_matching_dsym_is_closed_for_writing() {
    create_fixture "still-writing"
    write_plist "$SRC_ROOT/Config/Info.plist" "2.10.0" "154"
    TEST_INFOPLIST_FILE="Config/Info.plist"

    cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/bin/sh
printf 'UUID: CURRENT-UUID (arm64) %s\n' "$3"
EOF
    chmod +x "$FAKE_BIN/xcrun"

    cat > "$FAKE_BIN/lsof" <<'EOF'
#!/bin/sh
attempts=$(cat "$TEST_LSOF_ATTEMPTS" 2>/dev/null || printf 0)
attempts=$((attempts + 1))
printf '%s' "$attempts" > "$TEST_LSOF_ATTEMPTS"
if [ "$attempts" -lt 3 ]; then
    printf 'p123\nf4\naw\n'
    exit 0
fi
exit 1
EOF
    chmod +x "$FAKE_BIN/lsof"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected upload to wait for the dSYM writer: $OUTPUT"
    [ "$(cat "$LSOF_ATTEMPTS")" = "3" ] || fail "Expected three checks for an active dSYM writer"
    [ -f "$CLI_ARGS_FILE" ] || fail "Expected posthog-cli to run after the writer closed"
}

test_fails_when_dsym_never_matches() {
    create_fixture "not-ready"
    write_plist "$SRC_ROOT/Config/Info.plist" "2.10.0" "154"
    TEST_INFOPLIST_FILE="Config/Info.plist"
    TEST_DSYM_TIMEOUT="2"

    cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/bin/sh
case "$3" in
    *.dSYM/*) printf 'UUID: OLD-UUID (arm64) %s\n' "$3" ;;
    *) printf 'UUID: CURRENT-UUID (arm64) %s\n' "$3" ;;
esac
EOF
    chmod +x "$FAKE_BIN/xcrun"

    run_upload

    [ "$STATUS" -eq 1 ] || fail "Expected an unavailable dSYM to fail the build"
    [[ "$OUTPUT" == *"was not ready after 2 seconds"* ]] || fail "Expected a timeout error when the dSYM stays unavailable"
    [ ! -f "$CLI_ARGS_FILE" ] || fail "posthog-cli must not run with a stale dSYM"
}

test_checks_for_cli_before_waiting_for_dsym() {
    create_fixture "missing-cli"
    write_plist "$SRC_ROOT/Config/Info.plist" "2.10.0" "154"
    TEST_INFOPLIST_FILE="Config/Info.plist"
    rm "$HOME_DIR/.posthog/posthog-cli"

    cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/bin/sh
touch "$TEST_XCRUN_MARKER"
exit 1
EOF
    chmod +x "$FAKE_BIN/xcrun"

    run_upload

    [ "$STATUS" -eq 1 ] || fail "Expected a missing CLI to fail the build"
    [[ "$OUTPUT" == *"posthog-cli not found"* ]] || fail "Expected the missing CLI error"
    [ ! -f "$XCRUN_MARKER" ] || fail "dSYM polling must not run before checking for posthog-cli"
}

test_resolves_custom_build_setting_references() {
    create_fixture "custom-build-settings"
    write_plist "$SRC_ROOT/Config/Info.plist" "\$(APP_VERSION)" "\${BUILD_NUMBER}"
    TEST_INFOPLIST_FILE="$SRC_ROOT/Config/Info.plist"
    TEST_APP_VERSION="9.9.9"
    TEST_BUILD_NUMBER="321"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected custom build-setting versions to resolve: $OUTPUT"
    assert_file_contains_line "$CLI_ARGS_FILE" "9.9.9"
    assert_file_contains_line "$CLI_ARGS_FILE" "321"
}

test_prefers_processed_plist_when_preprocessing_is_enabled() {
    create_fixture "preprocessed"
    write_plist "$SRC_ROOT/Config/Info.plist" "APP_VERSION" "APP_BUILD"
    TEST_INFOPLIST_FILE="$SRC_ROOT/Config/Info.plist"
    TEST_INFOPLIST_PREPROCESS="YES"
    TEST_INFOPLIST_PATH="ExampleApp.app/Info.plist"
    write_plist "$TARGET_BUILD_DIR/$TEST_INFOPLIST_PATH" "2.10.0" "154"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected preprocessed versions to resolve: $OUTPUT"
    assert_file_contains_line "$CLI_ARGS_FILE" "2.10.0"
    assert_file_contains_line "$CLI_ARGS_FILE" "154"
}

test_skips_cli_lookup_when_build_does_not_emit_dsyms() {
    create_fixture "dwarf-only"
    write_plist "$SRC_ROOT/Config/Info.plist" "2.10.0" "154"
    TEST_INFOPLIST_FILE="$SRC_ROOT/Config/Info.plist"
    TEST_DEBUG_INFORMATION_FORMAT="dwarf"
    rm "$HOME_DIR/.posthog/posthog-cli"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected a DWARF-only build to skip symbol upload"
    [[ "$OUTPUT" == *"Skipping dSYM upload for debug information format 'dwarf'"* ]] || fail "Expected the DWARF-only skip message"
}

test_falls_back_for_unresolved_source_plist_versions() {
    create_fixture "fallback"
    write_plist "$SRC_ROOT/Config/Info.plist" "\$(MISSING_VERSION)" "\$(A)-\$(B)"
    TEST_INFOPLIST_FILE="$SRC_ROOT/Config/Info.plist"

    run_upload

    [ "$STATUS" -eq 0 ] || fail "Expected upload with fallback versions to succeed: $OUTPUT"
    assert_file_contains_line "$CLI_ARGS_FILE" "--release-version"
    assert_file_contains_line "$CLI_ARGS_FILE" "1.0"
    assert_file_contains_line "$CLI_ARGS_FILE" "--build"
    assert_file_contains_line "$CLI_ARGS_FILE" "1"
}

bash -n "$UPLOAD_SCRIPT"
test_waits_for_current_dsym_and_uses_source_plist_versions
test_waits_until_matching_dsym_is_closed_for_writing
test_fails_when_dsym_never_matches
test_checks_for_cli_before_waiting_for_dsym
test_resolves_custom_build_setting_references
test_prefers_processed_plist_when_preprocessing_is_enabled
test_skips_cli_lookup_when_build_does_not_emit_dsyms
test_falls_back_for_unresolved_source_plist_versions

echo "upload-symbols tests passed"
