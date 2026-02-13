#!/bin/bash
# Finds the UDID of the latest available iPhone simulator.
# Prefers the newest iOS runtime and picks the first iPhone device found.

set -euo pipefail

DEVICES_JSON=$(xcrun simctl list devices available -j)

echo "$DEVICES_JSON" | python3 -c "
import json, sys

devices = json.load(sys.stdin)['devices']

# Sort runtimes in descending order so we pick the newest iOS runtime first
for runtime in sorted(devices.keys(), reverse=True):
    if 'iOS' not in runtime:
        continue
    for device in devices[runtime]:
        if 'iPhone' in device['name']:
            print(device['udid'])
            sys.exit(0)

print('ERROR: No available iPhone simulator found', file=sys.stderr)
sys.exit(1)
"
