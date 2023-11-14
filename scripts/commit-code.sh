#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

if [[ $(git status) == *"nothing to commit"* ]]; then
    echo "Nothing to commit."
else
    echo "Going to push the changes."
    git fetch
    git commit -am "Update version"
    git push
fi
