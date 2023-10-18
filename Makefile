.PHONY: build buildSdk buildExample format swiftLint swiftFormat test lint

build: buildSdk buildExample

buildSdk:
	set -o pipefail && xcodebuild build -project PostHog.xcodeproj -scheme PostHog -destination 'platform=iOS Simulator,name=iPhone 14,OS=16.2' | xcpretty

buildExample:
	set -o pipefail && xcodebuild build -project PostHog.xcodeproj -scheme PostHogExample -destination 'platform=iOS Simulator,name=iPhone 14,OS=16.2' | xcpretty

format: swiftLint swiftFormat

swiftLint:
	swiftlint --fix

swiftFormat:
	swiftformat . --swiftversion 5.3

test:
	set -o pipefail && xcodebuild test -project PostHog.xcodeproj -scheme PostHog -destination 'platform=iOS Simulator,name=iPhone 14,OS=16.2' | xcpretty

lint:
	swiftformat . --lint --swiftversion 5.3 && swiftlint
