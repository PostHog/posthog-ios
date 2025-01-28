#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define output directories relative to script location
OUTPUT_DIR="$SCRIPT_DIR/build"
ARCHIVE_DIR="$OUTPUT_DIR/archives"
PROJECT_PATH="$SCRIPT_DIR/PostHogExampleExternalSDK.xcodeproj"

rm -rf "$OUTPUT_DIR" 
rm -rf "$ARCHIVE_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$ARCHIVE_DIR"

echo "Building for iOS devices..."
if ! xcodebuild archive \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ENABLE_MODULE_VERIFIER=YES \
        -project "$PROJECT_PATH" \
        -scheme ExternalSDK \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE_DIR/ExternalSDK-iOS.xcarchive" | xcpretty; then
        echo "Error: Failed to build framework for iOS Device"
fi

echo "Building for iOS simulator..."
if ! xcodebuild archive \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ENABLE_MODULE_VERIFIER=YES \
        -project "$PROJECT_PATH" \
        -scheme ExternalSDK \
        -configuration Release \
        -destination "generic/platform=iOS Simulator" \
        -archivePath "$ARCHIVE_DIR/ExternalSDK-iOS_Simulator.xcarchive" | xcpretty; then
        echo "Error: Failed to build framework for iOS Simulator"
fi

echo "Creating XCFramework..."
if ! xcodebuild -create-xcframework \
    -archive "$ARCHIVE_DIR/ExternalSDK-iOS.xcarchive" -framework ExternalSDK.framework \
    -archive "$ARCHIVE_DIR/ExternalSDK-iOS_Simulator.xcarchive" -framework ExternalSDK.framework \
    -output "$OUTPUT_DIR/bin/ExternalSDK.xcframework" | xcpretty; then
    echo "Error: Failed to create XCFramework"
    exit 1
fi

echo "XCFramework created at $OUTPUT_DIR/bin/ExternalSDK.xcframework"