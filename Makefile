.PHONY: build buildSdk buildExample format swiftLint swiftFormat test testOniOSSimulator testOnMacSimulator lint bootstrap releaseCocoaPods

build: buildSdk buildExample

buildSdk:
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun swift build --arch arm64 #macOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=xros | xcpretty #visionOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=tvos | xcpretty #tvOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHog -destination generic/platform=watchos | xcpretty #watchOS


buildExample:
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExample -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun xcodebuild build -scheme PostHogObjCExample -destination generic/platform=ios | xcpretty #ObjC
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExampleMacOS -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild build -scheme 'PostHogExampleWatchOS Watch App' -destination generic/platform=watchos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild build -scheme PostHogExampleTvOS -destination generic/platform=tvos | xcpretty #watchOS

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
