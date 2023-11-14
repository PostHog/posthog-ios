#!/bin/bash

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

NEW_VERSION="$1"

git tag -a ${NEW_VERSION} -m "${NEW_VERSION}"
git push && git push --tags
