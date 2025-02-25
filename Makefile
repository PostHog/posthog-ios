.PHONY: build buildSdk buildExamples format swiftLint swiftFormat test testOniOSSimulator testOnMacSimulator lint bootstrap releaseCocoaPods api

build: buildSdk buildExamples

buildSdk:
	set -o pipefail && xcrun xcodebuild -downloadAllPlatforms
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun swift build --arch arm64 #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=tvos | xcpretty #tvOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=watchos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination 'platform=visionOS Simulator,name=Apple Vision Pro' | xcpretty #visionOS

buildExamples: \
	buildExamplesPlatforms \
	buildExampleXCFramework \
	buildExamplePodsDynamic \
	buildExamplePodsStatic \

buildExamplesPlatforms:
	set -o pipefail && xcrun xcodebuild -downloadAllPlatforms
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExample -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExample -destination 'platform=visionOS Simulator,name=Apple Vision Pro' | xcpretty #visionOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogObjCExample -destination generic/platform=ios | xcpretty #ObjC
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleMacOS -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme 'PostHogExampleWatchOS Watch App' -destination generic/platform=watchos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleTvOS -destination generic/platform=tvos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleWithSPM -destination generic/platform=ios | xcpretty #SPM

buildExamplePodsDynamic:
	cd PostHogExampleWithPods && pod install && cd .. && \
	set -o pipefail && xcrun xcodebuild clean build \
		-workspace PostHogExampleWithPods/PostHogExampleWithPods.xcworkspace \
		-scheme PostHogExampleWithPods \
		-destination generic/platform=ios | xcpretty

buildExamplePodsStatic:
	cd PostHogExampleWithPods && \
	cp Podfile{,.backup} && \
	cp Podfile.static Podfile && \
	cp PostHogExampleWithPods.xcodeproj/project.pbxproj{,.backup} && \
	pod install && \
	cd .. && \
	set -o pipefail && xcrun xcodebuild clean build \
		-workspace PostHogExampleWithPods/PostHogExampleWithPods.xcworkspace \
		-scheme PostHogExampleWithPods \
		-destination generic/platform=ios | xcpretty && \
	cd PostHogExampleWithPods && \
	mv Podfile{.backup,} && \
	pod install && \
	mv PostHogExampleWithPods.xcodeproj/project.pbxproj{.backup,}

buildExampleXCFramework:
	./PostHogExampleExternalSDK/build_xcframework.sh
	set -o pipefail && xcrun xcodebuild clean build \
		-project ./PostHogExampleExternalSDK/SDKClient/PostHogExampleExternalSDKClient.xcodeproj \
		-scheme ExternalSDKClient \
		-destination "generic/platform=iOS Simulator" | xcpretty

format: swiftLint swiftFormat

swiftLint:
	swiftlint --fix

swiftFormat:
	swiftformat . --swiftversion 5.3

# use -test-iterations 10 if you want to run the tests multiple times
# use -only-testing:PostHogTests/PostHogQueueTest to run only a specific test
testOniOSSimulator:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' | xcpretty

testOnMacSimulator:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=macOS' | xcpretty

test:
	set -o pipefail && swift test --no-parallel -Xswiftc -DTESTING | xcpretty

lint:
	swiftformat . --lint --swiftversion 5.3 && swiftlint

# periphery scan --setup
# TODO: add periphery to the CI/commit prehooks
api:
	periphery scan

# requires gem and brew
# xcpretty needs 'export LANG=en_US.UTF-8'
bootstrap:
	gem install cocoapods
	gem install xcpretty
	brew install swiftlint
	brew install swiftformat
	brew install peripheryapp/periphery/periphery

# download SDKs and runtimes
# create Apple Vision Pro simulator if missing
# release pod
releaseCocoaPods:
	set -o pipefail && xcrun xcodebuild -downloadAllPlatforms 
	@if ! xcrun simctl list devices | grep -q "Apple Vision Pro"; then \
		LATEST_RUNTIME=$$(xcrun simctl list runtimes | grep "com.apple.CoreSimulator.SimRuntime.xrOS" | sort -r | head -n 1 | awk '{print $$NF}') && \
		xcrun simctl create "Apple Vision Pro" "Apple Vision Pro" "$$LATEST_RUNTIME"; \
	fi
	pod trunk push PostHog.podspec --allow-warnings