.PHONY: build buildSdk buildExamples format swiftLint swiftFormat swiftLintCheck swiftFormatCheck installSwiftLint installSwiftFormat test testDowngradeCompatibility testOniOSSimulator testOnMacSimulator lint bootstrap releaseCocoaPods api buildIOS

build: buildSdk buildExamples

buildIOS:
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=ios | xcpretty #ios

buildSdk:
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=ios | xcpretty #ios
	set -o pipefail && xcrun swift build --arch arm64 #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination generic/platform=macos | xcpretty #macOS
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHog -destination 'platform=macOS,variant=Mac Catalyst' | xcpretty #Mac Catalyst
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
	set -o pipefail && xcrun xcodebuild clean build -scheme PostHogExampleWithSPM -destination 'platform=macOS,variant=Mac Catalyst' | xcpretty #Mac Catalyst SPM

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

installSwiftLint:
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		brew install swiftlint; \
	fi

installSwiftFormat:
	@if ! command -v swiftformat >/dev/null 2>&1; then \
		brew install swiftformat; \
	fi

swiftLint: installSwiftLint
	swiftlint --fix

swiftFormat: installSwiftFormat
	swiftformat . --swiftversion 5.3

swiftLintCheck: installSwiftLint
	swiftlint

swiftFormatCheck: installSwiftFormat
	swiftformat . --lint --swiftversion 5.3

# use -only-testing:PostHogTests/PostHogQueueTest to run only a specific test
# -retry-tests-on-failure -test-iterations 3: a few tests assert real-time behaviour (autocapture
# debounce/flush windows) that can't be made deterministic; on slow, load-variable CI runners those
# windows occasionally slip. Rerun a *failed* test up to 3 times so a transient miss doesn't fail the
# job — a genuinely broken test fails all 3 and stays red. Retries can *mask* flakiness, so we tee the
# raw log to xcodebuild-ios.log; CI reads it back to surface tests that only passed after a retry (the
# macOS `test` job runs without retries, so a genuine flake still hard-fails there).
testOniOSSimulator:
	@device="$$(xcrun simctl list devices available | grep -E '^[[:space:]]*iPhone' | head -1 | sed -E 's/^[[:space:]]*//; s/ \(.*//')"; \
	[ -n "$$device" ] || { echo "No available iPhone simulator found; install one via Xcode or 'xcrun simctl create'."; exit 1; }; \
	echo "Testing on simulator: $$device"; \
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination "platform=iOS Simulator,name=$$device" -retry-tests-on-failure -test-iterations 3 | tee xcodebuild-ios.log | xcpretty

testOnMacSimulator:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=macOS' | xcpretty

# Usage: make test filter=<pattern>
# Examples:
#   make test                              						# Run all tests
#   make test filter=PostHogPropertiesSerializationTests        # Run specific test suite, class or method
test:
	set -o pipefail && swift test --no-parallel -Xswiftc -DTESTING $(if $(filter),--filter $(filter))

testDowngradeCompatibility:
	DOWNGRADE_REF="$${DOWNGRADE_REF:-3.48.0}" ./scripts/test-downgrade-compatibility.sh


lint: swiftFormatCheck swiftLintCheck

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