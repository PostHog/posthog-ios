#!/usr/bin/env bash
# Fails when a test source file under PostHogTests/ is not listed in PostHog.xcodeproj.
# SwiftPM discovers test files by path, but the Xcode iOS scheme only builds listed files,
# so an unlisted file is silently skipped on iOS.
set -euo pipefail

cd "$(dirname "$0")/.."

project="PostHog.xcodeproj/project.pbxproj"
tests_dir="PostHogTests"

[[ -f "$project" ]] || { echo "error: $project not found" >&2; exit 1; }
[[ -d "$tests_dir" ]] || { echo "error: $tests_dir/ not found" >&2; exit 1; }

checked=0
missing=()

while IFS= read -r file; do
    checked=$((checked + 1))
    name="$(basename "$file")"
    grep -qF "$name" "$project" || missing+=("$file")
done < <(find "$tests_dir" -type f -name '*.swift' | sort)

if [[ $checked -eq 0 ]]; then
    echo "error: no test files found in $tests_dir/" >&2
    exit 1
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: these test files are not in $project:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Add them to the PostHogTests target in Xcode." >&2
    exit 1
fi
echo "All $checked test files are registered in the Xcode project."
