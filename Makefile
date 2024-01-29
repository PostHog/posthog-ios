.PHONY: build buildSdk buildExamples format swiftLint swiftFormat test testOniOSSimulator testOnMacSimulator lint bootstrap releaseCocoaPods

build: buildSdk buildExamples

# set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination 'platform=visionOS Simulator,name=Apple Vision Pro' | xcpretty #visionOS
buildSdk:
	set -o pipefail && xcrun xcodebuild -downloadAllPlatforms
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun swift build --arch arm64 #macOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=tvos | xcpretty #tvOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=watchos | xcpretty #watchOS

buildExamples:
	set -o pipefail && xcrun xcodebuild -downloadAllPlatforms
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExample -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun xcodebuild build -scheme PostHogObjCExample -destination generic/platform=ios | xcpretty #ObjC
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExampleMacOS -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild build -scheme 'PostHogExampleWatchOS Watch App' -destination generic/platform=watchos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExampleTvOS -destination generic/platform=tvos | xcpretty #watchOS
	cd PostHogExampleWithPods && pod install
	cd ..
	set -o pipefail && xcrun xcodebuild build -workspace PostHogExampleWithPods/PostHogExampleWithPods.xcworkspace -scheme PostHogExampleWithPods -destination generic/platform=ios | xcpretty #CocoaPods
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExampleWithSPM -destination generic/platform=ios | xcpretty #SPM

format: swiftLint swiftFormat

swiftLint:
	swiftlint --fix

swiftFormat:
	swiftformat . --swiftversion 5.3

testOniOSSimulator:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0.1' | xcpretty

testOnMacSimulator:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=macOS' | xcpretty

test:
	swift test

lint:
	swiftformat . --lint --swiftversion 5.3 && swiftlint

# requires gem and brew
bootstrap:
	gem install xcpretty
	brew install swiftlint
	brew install swiftformat

releaseCocoaPods:
	pod trunk push PostHog.podspec --allow-warnings
