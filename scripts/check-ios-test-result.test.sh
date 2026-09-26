#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/check-ios-test-result.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check() {
    local expected="$1" status="$2" actual=0
    bash "$script" "$status" "$tmp/log" >"$tmp/output" 2>&1 || actual=$?
    if [[ "$actual" -ne "$expected" ]]; then
        echo "Expected exit $expected, got $actual for: $(<"$tmp/log")" >&2
        exit 1
    fi
}

printf '%s\n' '** TEST SUCCEEDED **' >"$tmp/log"
check 0 0

printf '%s\n' 'Executed 0 tests, with 0 failures' >"$tmp/log"
check 65 65

printf '%s\n' 'Executed 197 tests, with 0 failures' 'error: test runner crashed' >"$tmp/log"
check 65 65

printf '%s\n' 'Executed 197 tests, with 0 failures' 'Test "privacy" with 2 test cases failed after 0.1 seconds with 2 issues.' >"$tmp/log"
check 65 65

printf '%s\n' 'Test "privacy" with 2 test cases passed after 0.1 seconds.' >>"$tmp/log"
check 65 65

printf '%s\n' 'Test "one" failed' 'Test "two" passed' >"$tmp/log"
check 65 65
printf '%s\n' 'Test "one" passed' >>"$tmp/log"
check 65 65

printf '%s\n' "Test Case '-[Suite one]' failed" "Test Case '-[Suite one]' passed" >"$tmp/log"
check 65 65

rm "$tmp/log"
actual=0
bash "$script" 65 "$tmp/log" >"$tmp/output" 2>&1 || actual=$?
[[ "$actual" -eq 65 ]] || { echo 'Missing logs must fail' >&2; exit 1; }

echo 'check-ios-test-result tests passed'
