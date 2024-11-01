SIMULATOR_IOS_VERSION = $(shell xcrun simctl list | grep ^iOS | ruby -e 'puts /\(([0-9.]+).*\)/.match(STDIN.read.chomp.split("\n").last).to_a[1]')
SIMULATOR_ID = $(call udid_for,$(SIMULATOR_IOS_VERSION),iPhone [0-9]+ [^M])
TEST_ITERATIONS = 1

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

print-env: 
	@echo "Simulator iOS version: '$(SIMULATOR_IOS_VERSION)'"
	@echo "Simulator UUID: '$(SIMULATOR_ID)'"
	
swiftLint:
	swiftlint --fix

swiftFormat:
	swiftformat . --swiftversion 5.3

test-ios: print-env
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination platform="iOS Simulator,id=$(SIMULATOR_ID)" $(if $(filter-out 1,$(TEST_ITERATIONS)), -run-tests-until-failure -test-iterations $(TEST_ITERATIONS)) | xcpretty

test-macos: 
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=macOS' | xcpretty

test: 
	swift test | xcpretty

lint: 
	swiftformat . --lint --swiftversion 5.3 && swiftlint

# requires gem and brew
bootstrap:
	gem install xcpretty
	brew install swiftlint
	brew install swiftformat

releaseCocoaPods:
	pod trunk push PostHog.podspec --allow-warnings


define udid_for
$(shell xcrun simctl list --json devices available "$(1)" | jq -r --arg regex "$(2)" '
  .devices 
  | to_entries 
  | map(select(.value | length > 0)) 
  | map({key: .key, value: (.value | map(select(.name | test($$regex))))}) 
  | map(select(.value | length > 0)) 
  | .[0].value[0].udid
')
endef
