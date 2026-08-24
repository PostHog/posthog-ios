#!/bin/bash
#
# PostHog Debug Symbols Upload Script
# https://posthog.com/docs/error-tracking/upload-source-maps/ios
#
# Xcode Build Phase Setup:
#   SPM:        "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/posthog-ios/build-tools/upload-symbols.sh"
#   CocoaPods:  "${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh"
#
#
# Usage Examples:
#   Basic:          "${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh"
#   With source:    POSTHOG_INCLUDE_SOURCE=1 "${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh"
#   Skip conflicts: POSTHOG_SKIP_ON_CONFLICT=1 "${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh"
#   No release bind: POSTHOG_NO_RELEASE_BIND=1 "${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh"
#
# Build Settings (required):
#   DEBUG_INFORMATION_FORMAT = DWARF with dSYM File
#   ENABLE_USER_SCRIPT_SANDBOXING = NO (script traverses dSYM bundles)
#
# Environment Variables (optional):
#   POSTHOG_CLI_INSTALL_DIR - Custom directory containing posthog-cli binary
#   POSTHOG_INCLUDE_SOURCE - Set to "1" to include source files in dSYM upload
#   POSTHOG_SKIP_ON_CONFLICT - Set to "1" to skip symbol sets that already exist
#                              with different content instead of failing the build
#   POSTHOG_DSYM_TIMEOUT - Seconds to wait for the current app dSYM before failing (default: 60)
#   POSTHOG_NO_RELEASE_BIND - Set to "1" to upload symbol sets without binding them to the created
#                              release (via `dsym upload --no-release-bind`). The release is still
#                              created; the server resolves it from the `$app_version` /
#                              `$app_namespace` / `$app_build` the SDK sends on every event, so the
#                              uploaded chunks stay content-addressed and release-independent.
#                              Requires posthog-cli >= 0.10.0.
#

# Skip non-Release builds.
# This avoids network-bound work and potential auth/connectivity failures
# during local development builds.
# When CONFIGURATION is unset (e.g., manual/CI invocation outside Xcode), proceed with upload.
if [ -n "${CONFIGURATION}" ] && [ "${CONFIGURATION}" != "Release" ]; then
    echo "info: Skipping dSYM upload for configuration '${CONFIGURATION}' (not Release)."
    exit 0
fi

# Validate the path before looking for posthog-cli.
if [ -z "${DWARF_DSYM_FOLDER_PATH}" ]; then
    echo "warning: DWARF_DSYM_FOLDER_PATH not set"
    exit 0
fi

# A configured Xcode build that only emits DWARF has no dSYM to upload. Keep this check before CLI
# discovery so builds without symbols do not require posthog-cli.
if [ -n "${DEBUG_INFORMATION_FORMAT:-}" ] && [ "${DEBUG_INFORMATION_FORMAT}" != "dwarf-with-dsym" ]; then
    echo "info: Skipping dSYM upload for debug information format '${DEBUG_INFORMATION_FORMAT}'."
    exit 0
fi

# Find posthog-cli (Xcode doesn't load shell profiles)
# Priority: env var override > well-known location > npm global > PATH fallback
if [ -f "$HOME/.posthog/posthog-cli" ]; then
  PH_CLI_PATH="$HOME/.posthog/posthog-cli"
else
  # Add nvm paths (Xcode doesn't source shell profiles)
  for dir in "$HOME/.nvm/versions/node"/*/bin /opt/homebrew/Cellar/nvm/*/versions/node/*/bin; do
    [ -d "$dir" ] && export PATH="$dir:$PATH"
  done
  # Check if installed via npm -g @posthog/cli
  NPM_GLOBAL_PREFIX=$(npm prefix -g 2>/dev/null)
  if [ -n "$NPM_GLOBAL_PREFIX" ] && [ -f "$NPM_GLOBAL_PREFIX/bin/posthog-cli" ]; then
    PH_CLI_PATH="$NPM_GLOBAL_PREFIX/bin/posthog-cli"
  else
    # Check if installed as local dependency
    NPM_LOCAL_ROOT=$(npm root 2>/dev/null)
    if [ -n "$NPM_LOCAL_ROOT" ] && [ -f "$NPM_LOCAL_ROOT/.bin/posthog-cli" ]; then
      PH_CLI_PATH="$NPM_LOCAL_ROOT/.bin/posthog-cli"
    else
      # Fallback to searching common locations
      export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.posthog:$PATH"
      PH_CLI_PATH=$(command -v posthog-cli 2>/dev/null)
    fi
  fi
fi

if [ -z "$PH_CLI_PATH" ] || [ ! -x "$PH_CLI_PATH" ]; then
    echo "error: posthog-cli not found, install with: npm install -g @posthog/cli@latest"
    exit 1
fi

# Xcode can start this phase before dsymutil finishes. Declaring the dSYM as an input can create
# dependency cycles for apps with embedded extensions, so wait until the dSYM belongs to the current
# executable instead. Fail on timeout rather than letting a release ship without its symbols.
if [ "${DEBUG_INFORMATION_FORMAT:-}" = "dwarf-with-dsym" ] && [ -n "${DWARF_DSYM_FILE_NAME:-}" ] && [ -n "${EXECUTABLE_NAME:-}" ] && [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${EXECUTABLE_PATH:-}" ]; then
    POSTHOG_MAIN_DWARF="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${EXECUTABLE_NAME}"
    POSTHOG_APP_EXECUTABLE="${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}"
    POSTHOG_DSYM_TIMEOUT="${POSTHOG_DSYM_TIMEOUT:-60}"
    POSTHOG_LSOF_PATH="${POSTHOG_LSOF_PATH:-/usr/sbin/lsof}"
    POSTHOG_DSYM_WAITED=0
    POSTHOG_DSYM_READY=0

    case "$POSTHOG_DSYM_TIMEOUT" in
        ''|*[!0-9]*)
            echo "error: POSTHOG_DSYM_TIMEOUT must be a non-negative integer"
            exit 1
            ;;
    esac

    while [ "$POSTHOG_DSYM_WAITED" -le "$POSTHOG_DSYM_TIMEOUT" ]; do
        if [ -s "$POSTHOG_MAIN_DWARF" ] && [ -s "$POSTHOG_APP_EXECUTABLE" ]; then
            POSTHOG_DSYM_UUIDS=$(xcrun dwarfdump --uuid "$POSTHOG_MAIN_DWARF" 2>/dev/null | awk '/^UUID: / {print $2}' | sort)
            POSTHOG_APP_UUIDS=$(xcrun dwarfdump --uuid "$POSTHOG_APP_EXECUTABLE" 2>/dev/null | awk '/^UUID: / {print $2}' | sort)
            if [ -n "$POSTHOG_DSYM_UUIDS" ] && [ "$POSTHOG_DSYM_UUIDS" = "$POSTHOG_APP_UUIDS" ] && ! "$POSTHOG_LSOF_PATH" -F a -- "$POSTHOG_MAIN_DWARF" 2>/dev/null | grep -Eq '^a[uw]$'; then
                POSTHOG_DSYM_READY=1
                break
            fi
        fi

        if [ "$POSTHOG_DSYM_WAITED" -lt "$POSTHOG_DSYM_TIMEOUT" ]; then
            sleep 1
        fi
        POSTHOG_DSYM_WAITED=$((POSTHOG_DSYM_WAITED + 1))
    done

    if [ "$POSTHOG_DSYM_READY" -ne 1 ]; then
        echo "error: Main app dSYM was not ready after ${POSTHOG_DSYM_TIMEOUT} seconds: $POSTHOG_MAIN_DWARF"
        exit 1
    fi
fi

if [ ! -d "${DWARF_DSYM_FOLDER_PATH}" ]; then
    echo "warning: dSYM folder not found: ${DWARF_DSYM_FOLDER_PATH}"
    exit 0
fi

# Check if folder contains any dSYM bundles. This must run after the readiness wait because dsymutil
# may not have created the bundle when the upload phase starts.
if [ -z "$(find "${DWARF_DSYM_FOLDER_PATH}" -name '*.dSYM' -type d 2>/dev/null)" ]; then
    echo "info: No dSYM bundles found in ${DWARF_DSYM_FOLDER_PATH}"
    exit 0
fi

# Enforce minimum posthog-cli version (required for --release-name / --release-version flags)
MIN_POSTHOG_CLI_VERSION="0.7.7"
if [ "${POSTHOG_SKIP_ON_CONFLICT}" = "1" ]; then
    MIN_POSTHOG_CLI_VERSION="0.7.12"
fi
if [ "${POSTHOG_NO_RELEASE_BIND}" = "1" ]; then
    MIN_POSTHOG_CLI_VERSION="0.10.0"
fi
PH_CLI_VERSION=$("$PH_CLI_PATH" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)

if [ -z "$PH_CLI_VERSION" ]; then
    echo "error: could not determine posthog-cli version. Upgrade: npm install -g @posthog/cli@latest"
    exit 1
fi

# Compare versions: lowest sorted == min required means current >= min
LOWEST=$(printf '%s\n%s\n' "$MIN_POSTHOG_CLI_VERSION" "$PH_CLI_VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)
if [ "$LOWEST" != "$MIN_POSTHOG_CLI_VERSION" ]; then
    echo "error: posthog-cli >= ${MIN_POSTHOG_CLI_VERSION} required (found ${PH_CLI_VERSION}). Upgrade: npm install -g @posthog/cli@latest"
    exit 1
fi

resolve_source_plist_value() {
    local key="$1"
    local plist_path="${INFOPLIST_FILE:-}"
    local value
    local token
    local name
    local replacement
    local prefix
    local suffix

    # Bare C preprocessor macros cannot be expanded safely here, and the product plist may belong to
    # a previous build. Preserve the existing Xcode-setting fallback for preprocessed plists.
    if [ "${INFOPLIST_PREPROCESS:-}" = "YES" ] || [ -z "$plist_path" ]; then
        return
    fi
    if [[ "$plist_path" != /* ]]; then
        if [ -z "${SRCROOT:-}" ]; then
            return
        fi
        plist_path="${SRCROOT}/${plist_path}"
    fi
    if [ ! -f "$plist_path" ]; then
        return
    fi

    value=$(/usr/libexec/PlistBuddy -c "Print :${key}" "$plist_path" 2>/dev/null) || return
    while [[ "$value" =~ (\$\(([A-Za-z_][A-Za-z0-9_]*)\)|\$\{([A-Za-z_][A-Za-z0-9_]*)\}) ]]; do
        token=${BASH_REMATCH[1]}
        name=${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}
        replacement=$(printenv "$name" 2>/dev/null) || return
        prefix=${value%%"$token"*}
        suffix=${value#*"$token"}
        value="${prefix}${replacement}${suffix}"
    done
    if [ -z "$value" ] || [[ "$value" == *"\$("* ]] || [[ "$value" == *"\${"* ]]; then
        return
    fi
    printf '%s' "$value"
}

POSTHOG_RELEASE_VERSION=$(resolve_source_plist_value "CFBundleShortVersionString")
POSTHOG_BUILD_VERSION=$(resolve_source_plist_value "CFBundleVersion")

# Build CLI arguments as an array so paths with spaces are preserved.
CLI_ARGS=(--directory "${DWARF_DSYM_FOLDER_PATH}")

# Pass main target dSYM name for accurate version extraction
if [ -n "${DWARF_DSYM_FILE_NAME}" ]; then
    CLI_ARGS+=(--main-dsym "${DWARF_DSYM_FILE_NAME}")
fi

# Prefer literal values from the source Info.plist. EAS remote versioning can update these values
# without changing MARKETING_VERSION or CURRENT_PROJECT_VERSION.
if [ -n "${PRODUCT_BUNDLE_IDENTIFIER}" ]; then
    CLI_ARGS+=(--release-name "${PRODUCT_BUNDLE_IDENTIFIER}")
fi
if [ -n "$POSTHOG_RELEASE_VERSION" ]; then
    CLI_ARGS+=(--release-version "$POSTHOG_RELEASE_VERSION")
elif [ -n "${MARKETING_VERSION}" ]; then
    CLI_ARGS+=(--release-version "${MARKETING_VERSION}")
fi
if [ -n "$POSTHOG_BUILD_VERSION" ]; then
    CLI_ARGS+=(--build "$POSTHOG_BUILD_VERSION")
elif [ -n "${CURRENT_PROJECT_VERSION}" ]; then
    CLI_ARGS+=(--build "${CURRENT_PROJECT_VERSION}")
fi
# Include source if requested via env var
if [ "${POSTHOG_INCLUDE_SOURCE}" = "1" ]; then
    CLI_ARGS+=(--include-source)
fi
if [ "${POSTHOG_SKIP_ON_CONFLICT}" = "1" ]; then
    CLI_ARGS+=(--skip-on-conflict)
fi

# Optionally upload the symbol sets without binding them to the release. The release is still
# created, and the server resolves it from the $app_version / $app_namespace / $app_build the SDK
# sends on every event, so nothing is written into the built bundle.
if [ "${POSTHOG_NO_RELEASE_BIND}" = "1" ]; then
    CLI_ARGS+=(--no-release-bind)
fi

"${PH_CLI_PATH}" dsym upload "${CLI_ARGS[@]}" || exit 1
