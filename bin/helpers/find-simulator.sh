#!/bin/bash
# Finds the UDID of the latest available simulator for a given platform.
# Usage: find-simulator.sh [ios|tvos]
# Defaults to ios if no argument is provided.

set -euo pipefail

PLATFORM="${1:-ios}"

DEVICES_JSON=$(xcrun simctl list devices available -j)

echo "$DEVICES_JSON" | python3 -c "
import json, sys

platform = '$PLATFORM'
devices = json.load(sys.stdin)['devices']

# Map platform argument to runtime keyword and device name prefix
platform_config = {
    'ios':  {'runtime': 'iOS', 'device_prefix': 'iPhone'},
    'tvos': {'runtime': 'tvOS', 'device_prefix': 'Apple TV'},
}

if platform not in platform_config:
    print(f'ERROR: Unknown platform \"{platform}\". Use: {list(platform_config.keys())}', file=sys.stderr)
    sys.exit(1)

config = platform_config[platform]

# Sort runtimes in descending order so we pick the newest runtime first
for runtime in sorted(devices.keys(), reverse=True):
    if config['runtime'] not in runtime:
        continue
    for device in devices[runtime]:
        if config['device_prefix'] in device['name']:
            print(device['udid'])
            sys.exit(0)

print(f'ERROR: No available {platform} simulator found', file=sys.stderr)
sys.exit(1)
"
