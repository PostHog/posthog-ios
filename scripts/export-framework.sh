#!/bin/bash

set -e

rm -rf ./build
rm -rf ./PostHog.xcframework
rm -f PostHog.xcframework.zip


xcodebuild archive \
    -scheme PostHog \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath './build/PostHog.framework-iphoneos.xcarchive' \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

xcodebuild archive \
    -scheme PostHog \
    -configuration Release \
    -sdk iphonesimulator \
    -archivePath './build/PostHog.framework-iphonesimulator.xcarchive' \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO


xcodebuild -create-xcframework \
    -framework './build/PostHog.framework-iphonesimulator.xcarchive/Products/Library/Frameworks/PostHog.framework' \
    -framework './build/PostHog.framework-iphoneos.xcarchive/Products/Library/Frameworks/PostHog.framework' \
    -output './PostHog.xcframework'

    # -framework './build/PostHog.framework-catalyst.xcarchive/Products/Library/Frameworks/PostHog.framework' \


rm -rf ../posthog-ios/PostHog.xcframework
cp -r ./PostHog.xcframework ../posthog-ios/PostHog.xcframework