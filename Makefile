XC_ARGS := -workspace PostHog.xcworkspace GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=YES
IOS_XCARGS := $(XC_ARGS) -destination "platform=iOS Simulator,name=iPhone 11" -sdk iphonesimulator
TVOS_XCARGS := $(XC_ARGS) -destination "platform=tvOS Simulator,name=Apple TV"
XC_BUILD_ARGS := -scheme PostHog ONLY_ACTIVE_ARCH=NO
XC_TEST_ARGS := GCC_GENERATE_TEST_COVERAGE_FILES=YES SWIFT_VERSION=4.2 RUN_E2E_TESTS=$(RUN_E2E_TESTS) WEBHOOK_AUTH_USERNAME=$(WEBHOOK_AUTH_USERNAME)

bootstrap:
	.buildscript/bootstrap.sh

dependencies: Podfile PostHog.podspec
	pod install

lint:
	pod lib lint --allow-warnings

carthage:
	carthage build --no-skip-current

archive: carthage
	carthage archive PostHog

clean-ios:
	set -o pipefail && xcodebuild $(IOS_XCARGS) -scheme PostHog clean | xcpretty

clean-tvos:
	set -o pipefail && xcodebuild $(TVOS_XCARGS) -scheme PostHog clean | xcpretty

clean: clean-ios clean-tvos

build-ios:
	set -o pipefail && xcodebuild $(IOS_XCARGS) $(XC_BUILD_ARGS) | xcpretty

build-tvos:
	set -o pipefail && xcodebuild $(TVOS_XCARGS) $(XC_BUILD_ARGS) | xcpretty

build: build-ios build-tvos

test-ios:
	@set -o pipefail && xcodebuild test $(IOS_XCARGS) -scheme PostHogTests $(XC_TEST_ARGS) | xcpretty --report junit

test-tvos:
	@set -o pipefail && xcodebuild test $(TVOS_XCARGS) -scheme PostHogTestsTVOS $(XC_TEST_ARGS) | xcpretty --report junit

test: test-ios test-tvos

xctest:
	xctool $(IOS_XCARGS) -scheme PostHogTests $(XC_TEST_ARGS) run-tests -sdk iphonesimulator

.PHONY: bootstrap dependencies lint carthage archive build test xctest clean
