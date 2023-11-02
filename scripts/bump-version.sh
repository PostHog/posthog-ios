#!/bin/bash

# ./scripts/bump-version.sh <new version>
# eg ./scripts/bump-version.sh "3.0.0-alpha.1"

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

NEW_VERSION="$1"

# Replace `postHogVersion` with the given version
perl -pi -e "s/postHogVersion = \".*\"/postHogVersion = \"$NEW_VERSION\"/" PostHog/PostHogVersion.swift

# Replace `s.version` with the given version
perl -pi -e "s/s.version          = \".*\"/s.version          = \"$NEW_VERSION\"/" PostHog.podspec
