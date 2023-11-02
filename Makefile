.PHONY: build buildSdk buildExample format swiftLint swiftFormat test testOnSimulator lint bootstrap releaseCocoaPods

build: buildSdk buildExample

buildSdk:
	set -o pipefail && xcodebuild build -project PostHog.xcodeproj -scheme PostHog -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0.1' | xcpretty

buildExample:
	set -o pipefail && xcodebuild build -project PostHog.xcodeproj -scheme PostHogExample -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0.1' | xcpretty

format: swiftLint swiftFormat

swiftLint:
	swiftlint --fix

swiftFormat:
	swiftformat . --swiftversion 5.3

testOnSimulator:
	set -o pipefail && xcodebuild test -project PostHog.xcodeproj -scheme PostHog -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0.1' | xcpretty

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
