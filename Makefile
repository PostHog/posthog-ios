.PHONY: build buildSdk buildExamples format swiftLint swiftFormat test testOniOSSimulator testOnMacSimulator lint bootstrap releaseCocoaPods api

build: buildSdk buildExamples

buildSdk:
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun swift build --arch arm64 #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=tvos | xcpretty #tvOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=watchos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=xros | xcpretty #visionOS

buildExamples: \
	buildExamplesPlatforms \
	buildExampleXCFramework \
	buildExamplePods \

buildExamplePods: \
	buildExamplePodsStaticLib \
	buildExamplePodsStaticFramework \
	buildExamplePodsDynamicFramework \

buildExamplesPlatforms:
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExample -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleVisionOS -destination generic/platform=xros | xcpretty #visionOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogObjCExample -destination generic/platform=ios | xcpretty #ObjC
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleMacOS -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme 'PostHogExampleWatchOS Watch App' -destination generic/platform=watchos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleTvOS -destination generic/platform=tvos | xcpretty #watchOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleWithSPM -destination generic/platform=ios | xcpretty #SPM

buildExamplePodsDynamicFramework:
	cd PostHogExampleWithPods && \
	USE_FRAMEWORKS=dynamic pod install && cd .. && \
	set -o pipefail && xcrun xcodebuild clean build \
		-workspace PostHogExampleWithPods/PostHogExampleWithPods.xcworkspace \
		-scheme PostHogExampleWithPods \
		-destination generic/platform=ios | xcpretty

buildExamplePodsStaticFramework:
	cd PostHogExampleWithPods && \
	USE_FRAMEWORKS=static pod install && cd .. && \
	set -o pipefail && xcrun xcodebuild clean build \
		-workspace PostHogExampleWithPods/PostHogExampleWithPods.xcworkspace \
		-scheme PostHogExampleWithPods \
		-destination generic/platform=ios | xcpretty

buildExamplePodsStaticLib: 
	cd PostHogExampleWithPods && \
	pod install && cd .. && \
	set -o pipefail && xcrun xcodebuild clean build \
		-workspace PostHogExampleWithPods/PostHogExampleWithPods.xcworkspace \
		-scheme PostHogExampleWithPods \
		-destination generic/platform=ios | xcpretty

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
	$(eval SIMULATOR_UDID := $(shell xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(dev['udid'] for r,devs in sorted(d.items(),reverse=True) if 'iOS' in r for dev in devs if 'iPhone' in dev['name']))"))
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=iOS Simulator,id=$(SIMULATOR_UDID)'

testOnMacSimulator:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=macOS'

# Usage: make test filter=<pattern>
# Examples:
#   make test                              						# Run all tests
#   make test filter=PostHogPropertiesSerializationTests        # Run specific test suite, class or method
test:
	set -o pipefail && swift test --no-parallel -Xswiftc -DTESTING $(if $(filter),--filter $(filter))


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