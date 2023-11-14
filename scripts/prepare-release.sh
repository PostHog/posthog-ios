#!/bin/bash

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

NEW_VERSION="$1"

# bump version
./scripts/bump-version.sh $NEW_VERSION

# commit changes
./scripts/commit-code.sh

# create and push tag
./scripts/create-tag.sh $NEW_VERSION
