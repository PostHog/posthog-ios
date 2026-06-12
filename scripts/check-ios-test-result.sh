#!/usr/bin/env bash
set -euo pipefail

status="${1:?usage: $0 <xcodebuild-status> [xcodebuild-log]}"
log="${2:-xcodebuild-ios.log}"

if [[ "$status" -eq 0 ]]; then
    exit 0
fi

if [[ ! -f "$log" ]]; then
    echo "xcodebuild failed with status $status and no log was found at $log" >&2
    exit "$status"
fi

passed_file="$(mktemp)"
failed_file="$(mktemp)"
unresolved_file="$(mktemp)"
cleanup() {
    rm -f "$passed_file" "$failed_file" "$unresolved_file"
}
trap cleanup EXIT

{
    grep -oE 'Test "[^"]+" passed' "$log" | sed -E 's/^Test "//; s/" passed$//' || true
    grep -oE "Test Case '[^']+' passed" "$log" | sed -E "s/^Test Case '//; s/' passed$//" || true
} | sort -u >"$passed_file"

{
    grep -oE 'Test "[^"]+" failed' "$log" | sed -E 's/^Test "//; s/" failed$//' || true
    grep -oE "Test Case '[^']+' failed" "$log" | sed -E "s/^Test Case '//; s/' failed$//" || true
} | sort -u >"$failed_file"

comm -23 "$failed_file" "$passed_file" >"$unresolved_file"

if [[ ! -s "$failed_file" ]]; then
    echo "xcodebuild failed with status $status, but no failed tests were found in $log" >&2
    exit "$status"
fi

if [[ -s "$unresolved_file" ]]; then
    echo "xcodebuild failed with status $status; these tests did not pass on retry:" >&2
    cat "$unresolved_file" >&2
    exit "$status"
fi

echo "warning: xcodebuild exited with status $status, but all failed tests passed on retry; treating as success." >&2
exit 0
