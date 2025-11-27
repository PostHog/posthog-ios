#!/bin/bash
#
# Strips symbols from PostHogExample app and PostHog framework
# to simulate App Store distribution for testing symbolication
#

set -e

# When run from Xcode build phase, use environment variables
# When run manually, find derived data
if [ -n "$BUILT_PRODUCTS_DIR" ]; then
    # Running as Xcode build phase
    BUILD_DIR="$BUILT_PRODUCTS_DIR"
    APP_BINARY="$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
    echo "📁 Running as Xcode build phase"
    echo "   Build dir: $BUILD_DIR"
else
    # Running manually
    DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
    POSTHOG_DERIVED=$(find "$DERIVED_DATA_BASE" -maxdepth 1 -name "PostHog-*" -type d | head -1)

    if [ -z "$POSTHOG_DERIVED" ]; then
        echo "❌ Could not find PostHog derived data folder"
        echo "   Make sure you've built the project first"
        exit 1
    fi

    echo "📁 Found derived data: $POSTHOG_DERIVED"

    # Configuration (default to Release-iphonesimulator)
    CONFIG="${1:-Release-iphonesimulator}"
    BUILD_DIR="$POSTHOG_DERIVED/Build/Products/$CONFIG"

    if [ ! -d "$BUILD_DIR" ]; then
        echo "❌ Build directory not found: $BUILD_DIR"
        echo "   Available configurations:"
        ls "$POSTHOG_DERIVED/Build/Products/" 2>/dev/null || echo "   (none)"
        exit 1
    fi

    APP_BINARY="$BUILD_DIR/PostHogExample.app/PostHogExample"
fi

# Framework paths
FRAMEWORK_BINARY="$BUILD_DIR/PostHog.framework/PostHog"

echo ""
echo "🔍 Checking binaries..."

# Check app binary
if [ -f "$APP_BINARY" ]; then
    SYMBOLS_BEFORE=$(nm "$APP_BINARY" 2>/dev/null | wc -l | tr -d ' ')
    echo "   App binary: $APP_BINARY"
    echo "   Symbols before: $SYMBOLS_BEFORE"
else
    echo "❌ App binary not found: $APP_BINARY"
    exit 1
fi

# Check framework binary
if [ -f "$FRAMEWORK_BINARY" ]; then
    FW_SYMBOLS_BEFORE=$(nm "$FRAMEWORK_BINARY" 2>/dev/null | wc -l | tr -d ' ')
    echo "   Framework binary: $FRAMEWORK_BINARY"
    echo "   Symbols before: $FW_SYMBOLS_BEFORE"
else
    echo "⚠️  Framework binary not found (embedded in app?)"
    FRAMEWORK_BINARY=""
fi

# Also check for embedded framework
if [ -n "$TARGET_BUILD_DIR" ]; then
    EMBEDDED_FRAMEWORK="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks/PostHog.framework/PostHog"
else
    EMBEDDED_FRAMEWORK="$BUILD_DIR/PostHogExample.app/Frameworks/PostHog.framework/PostHog"
fi
if [ -f "$EMBEDDED_FRAMEWORK" ]; then
    EMB_SYMBOLS_BEFORE=$(nm "$EMBEDDED_FRAMEWORK" 2>/dev/null | wc -l | tr -d ' ')
    echo "   Embedded framework: $EMBEDDED_FRAMEWORK"
    echo "   Symbols before: $EMB_SYMBOLS_BEFORE"
fi

echo ""
echo "✂️  Stripping symbols..."

# Strip app binary
strip -x "$APP_BINARY"
SYMBOLS_AFTER=$(nm "$APP_BINARY" 2>/dev/null | wc -l | tr -d ' ')
echo "   App: $SYMBOLS_BEFORE → $SYMBOLS_AFTER symbols"

# Strip framework binary (if exists)
if [ -n "$FRAMEWORK_BINARY" ] && [ -f "$FRAMEWORK_BINARY" ]; then
    strip -x "$FRAMEWORK_BINARY"
    FW_SYMBOLS_AFTER=$(nm "$FRAMEWORK_BINARY" 2>/dev/null | wc -l | tr -d ' ')
    echo "   Framework: $FW_SYMBOLS_BEFORE → $FW_SYMBOLS_AFTER symbols"
fi

# Strip embedded framework (if exists)
if [ -f "$EMBEDDED_FRAMEWORK" ]; then
    strip -x "$EMBEDDED_FRAMEWORK"
    EMB_SYMBOLS_AFTER=$(nm "$EMBEDDED_FRAMEWORK" 2>/dev/null | wc -l | tr -d ' ')
    echo "   Embedded framework: $EMB_SYMBOLS_BEFORE → $EMB_SYMBOLS_AFTER symbols"
fi

echo ""
echo "🔏 Re-signing binaries (required after stripping)..."

# Re-sign app binary
codesign --force --sign - "$APP_BINARY"
echo "   App re-signed"

# Re-sign framework binary (if exists)
if [ -n "$FRAMEWORK_BINARY" ] && [ -f "$FRAMEWORK_BINARY" ]; then
    codesign --force --sign - "$FRAMEWORK_BINARY"
    echo "   Framework re-signed"
fi

# Re-sign embedded framework (if exists)  
if [ -f "$EMBEDDED_FRAMEWORK" ]; then
    # Need to sign the framework bundle, not just the binary
    EMBEDDED_FRAMEWORK_DIR=$(dirname "$EMBEDDED_FRAMEWORK")
    codesign --force --sign - "$EMBEDDED_FRAMEWORK_DIR"
    echo "   Embedded framework re-signed"
fi

# Re-sign the whole app bundle
if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$FULL_PRODUCT_NAME" ]; then
    APP_BUNDLE="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
else
    APP_BUNDLE="$BUILD_DIR/PostHogExample.app"
fi

if [ -d "$APP_BUNDLE" ]; then
    codesign --force --sign - "$APP_BUNDLE"
    echo "   App bundle re-signed"
fi

echo ""
echo "✅ Done! Symbols stripped and binaries re-signed."
echo ""
echo "📝 To test:"
echo "   1. Run the app from Xcode (it will use the stripped binary)"
echo "   2. Trigger an error capture"
echo "   3. Check that stack frames show only addresses (no function names)"
echo ""
echo "⚠️  Note: Rebuilding will restore symbols. Run this script again after each build."
