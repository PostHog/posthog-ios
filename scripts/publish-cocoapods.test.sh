#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["jobs"]["publish-cocoapods"]["steps"].find { |step| step["id"] == "publish" }.fetch("run")' \
    "$root/.github/workflows/release.yml" >"$tmp/publish.sh"

mkdir "$tmp/bin"
cat >"$tmp/bin/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PUSH_ERROR" >&2
exit "$PUSH_STATUS"
EOF
cat >"$tmp/bin/pod" <<'EOF'
#!/usr/bin/env bash
echo info >>"$RUNNER_TEMP/calls"
if [[ "$ON_TRUNK" == true ]]; then
    echo '    - 3.93.5 (2026-11-04)'
fi
EOF
cat >"$tmp/bin/sleep" <<'EOF'
#!/usr/bin/env bash
echo sleep >>"$RUNNER_TEMP/calls"
EOF
chmod +x "$tmp/bin/"*

check() {
    local error="$1" push_status="$2" on_trunk="$3" expected_status="$4" expected_polls="$5" expected_sleeps="$6" expected_published="$7"
    local status=0 polls=0 sleeps=0 published=false
    : >"$tmp/calls"
    : >"$tmp/github-output"
    PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp" GITHUB_OUTPUT="$tmp/github-output" \
        RELEASE_VERSION=3.93.5 PUSH_ERROR="$error" PUSH_STATUS="$push_status" ON_TRUNK="$on_trunk" \
        bash "$tmp/publish.sh" >"$tmp/output" 2>&1 || status=$?
    polls=$(grep -c '^info$' "$tmp/calls" || true)
    sleeps=$(grep -c '^sleep$' "$tmp/calls" || true)
    if grep -q '^published=true$' "$tmp/github-output"; then
        published=true
    fi
    if [[ "$status" != "$expected_status" || "$polls" != "$expected_polls" || "$sleeps" != "$expected_sleeps" || "$published" != "$expected_published" ]]; then
        printf 'Failed for %q: status=%s polls=%s sleeps=%s published=%s\n' "$error" "$status" "$polls" "$sleeps" "$published" >&2
        exit 1
    fi
}

check 'CocoaPods Trunk is in read only mode' 1 false 1 0 0 false
check 'CocoaPods Trunk is in its read-only test week' 1 false 1 0 0 false
check 'CocoaPods Trunk is READ ONLY' 1 true 1 0 0 false
check '' 0 false 0 0 0 true
check 'Response verification timed out' 1 true 0 1 0 true
check 'Response verification timed out' 1 false 1 10 9 false

echo 'CocoaPods publish tests passed'
