#!/usr/bin/env bash
# Runs the PostHog test target on an iOS simulator once, then reruns only the XCTest cases that
# failed or crashed, each rerun in a fresh test process.
#
# The first test-host launch on a fresh CI simulator can stall the test process for minutes, which
# fails whichever tests are waiting on a timeout at the time. A short warm-up run in its own process
# absorbs that stall before the full suite starts.
#
# Swift Testing failures are never retried: rerunning Swift Testing suites in the same process
# reinstalls irreversible swizzles. XCTest (Quick) cases are retried because CI simulators
# occasionally deliver a stubbed request tens of seconds late, past the tests' 30s wait.
set -uo pipefail

log="${1:-xcodebuild-ios.log}"
max_retries=2
max_retried_cases=10

device="$(xcrun simctl list devices available | grep -E '^[[:space:]]*iPhone' | head -1 | sed -E 's/^[[:space:]]*//; s/ \(.*//')"
if [[ -z "$device" ]]; then
    echo "No available iPhone simulator found; install one via Xcode or 'xcrun simctl create'." >&2
    exit 1
fi
echo "Testing on simulator: $device"
destination="platform=iOS Simulator,name=$device"

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b

xcrun xcodebuild build-for-testing -scheme PostHog -destination "$destination" 2>&1 | tee "$log" | xcpretty
status=$?
if [[ "$status" -ne 0 ]]; then
    exec scripts/check-ios-test-result.sh "$status" "$log"
fi

echo "Warming up the test host"
xcrun xcodebuild test-without-building -scheme PostHog -destination "$destination" -parallel-testing-enabled NO \
    -only-testing:PostHogTests/UUIDTest 2>&1 | xcpretty || true

xcrun xcodebuild test-without-building -scheme PostHog -destination "$destination" -parallel-testing-enabled NO 2>&1 | tee -a "$log" | xcpretty
status=$?
if [[ "$status" -eq 0 ]]; then
    exit 0
fi

# Prints `PostHogTests/<Class>/<method>` for every XCTest case in the log that failed, or that was
# running when the test process crashed.
failed_xctest_cases() {
    awk '
        match($0, /^Test Case .-\[PostHogTests\.[A-Za-z0-9_]+ [^]]+\]. started\./) {
            running = $0
            sub(/^Test Case .-\[PostHogTests\./, "", running)
            sub(/\]. started\..*/, "", running)
            next
        }
        match($0, /^Test Case .-\[PostHogTests\.[A-Za-z0-9_]+ [^]]+\]. failed/) {
            failed = $0
            sub(/^Test Case .-\[PostHogTests\./, "", failed)
            sub(/\]. failed.*/, "", failed)
            print failed
            running = ""
            next
        }
        /^Test Case .* passed/ { running = ""; next }
        /^Restarting after unexpected exit, crash, or test timeout/ {
            if (running != "") print running
            running = ""
        }
    ' "$1" | sed -E 's|^([A-Za-z0-9_]+) |PostHogTests/\1/|' | sort -u
}

if grep -qE '^✘ ' "$log"; then
    echo "Swift Testing failures are not retried." >&2
    exec scripts/check-ios-test-result.sh "$status" "$log"
fi

cases="$(failed_xctest_cases "$log")"
count="$(printf '%s' "$cases" | grep -c . || true)"
if [[ "$count" -eq 0 || "$count" -gt "$max_retried_cases" ]]; then
    echo "Found $count failed XCTest case(s); retrying only between 1 and $max_retried_cases." >&2
    exec scripts/check-ios-test-result.sh "$status" "$log"
fi

only_testing=()
while IFS= read -r test_case; do
    only_testing+=("-only-testing:$test_case")
done <<< "$cases"

for attempt in $(seq 1 "$max_retries"); do
    echo "Retrying $count failed XCTest case(s), attempt $attempt of $max_retries:"
    printf '  %s\n' "${only_testing[@]#-only-testing:}"
    echo "=== Retry attempt $attempt ===" >> "$log"
    xcrun xcodebuild test-without-building -scheme PostHog -destination "$destination" -parallel-testing-enabled NO "${only_testing[@]}" 2>&1 | tee -a "$log" | xcpretty
    status=$?
    if [[ "$status" -eq 0 ]]; then
        exit 0
    fi
done

exec scripts/check-ios-test-result.sh "$status" "$log"
