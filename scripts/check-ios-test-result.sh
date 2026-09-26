#!/usr/bin/env bash
set -euo pipefail

status="${1:?usage: $0 <xcodebuild-status> [xcodebuild-log]}"
log="${2:-xcodebuild-ios.log}"

if [[ "$status" -eq 0 ]]; then
    exit 0
fi

# Display names are not unique across suites or parameter cases. A passing line
# cannot prove that a different failed line was a successful retry.
if [[ -f "$log" ]]; then
    echo "xcodebuild failed with status $status; inspect $log and the test result bundle." >&2
else
    echo "xcodebuild failed with status $status and no log was found at $log" >&2
fi
exit "$status"
