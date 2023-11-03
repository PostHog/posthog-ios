#!/bin/bash
set -euo pipefail

CURRENT_TAG="$1"
TEMP_TAG="${CURRENT_TAG}-temp"

echo "Going to push the tag changes."
git config --global user.name 'PostHog Github Bot'
git config --global user.email 'github-bot@posthog.com'
git fetch
git checkout ${CURRENT_TAG}
# Create a new temporary tag after pushing the changes from the previous tag (bump version)
git tag -a ${TEMP_TAG} -m "${TEMP_TAG}"
# Remove the current tag
git tag -d ${CURRENT_TAG}
# Remove the current tag in remote machine
git push --delete origin ${CURRENT_TAG}
# Create a new tag that points to the temporary tag
git tag ${CURRENT_TAG} ${TEMP_TAG}
# Remove temporary tag
git tag -d ${TEMP_TAG}
# Propapate new tag to remote machine
git push --tags
