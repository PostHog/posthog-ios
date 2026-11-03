#!/usr/bin/env bash
# Fails when a test source file is not compiled by PostHog.xcodeproj.
# SwiftPM discovers test files by path, but the Xcode iOS scheme only builds listed files,
# so an unlisted file is silently skipped on iOS.
set -euo pipefail

cd "$(dirname "$0")/.."

project="PostHog.xcodeproj/project.pbxproj"

[[ -f "$project" ]] || { echo "error: $project not found" >&2; exit 1; }
for dir in PostHogTests PostHogTestsObjC; do
    [[ -d "$dir" ]] || { echo "error: $dir/ not found" >&2; exit 1; }
done

checked=0
missing=()

while IFS= read -r file; do
    checked=$((checked + 1))
    # Each compiled file has a build entry like "/* Foo.swift in Sources */".
    grep -qF "/* $(basename "$file") in Sources */" "$project" || missing+=("$file")
done < <(find PostHogTests PostHogTestsObjC -type f \( -name '*.swift' -o -name '*.m' \) | sort)

if [[ $checked -eq 0 ]]; then
    echo "error: no test files found" >&2
    exit 1
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: these test files are not compiled by $project:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Add them to the PostHogTests target in Xcode." >&2
    exit 1
fi
echo "All $checked test files are registered in the Xcode project."
