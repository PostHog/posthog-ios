[![Version](https://img.shields.io/cocoapods/v/PostHog.svg?style=flat)](https://cocoapods.org//pods/PostHog)
[![License](https://img.shields.io/cocoapods/l/PostHog.svg?style=flat)](http://cocoapods.org/pods/PostHog)
[![SwiftPM Compatible](https://img.shields.io/badge/SwiftPM-Compatible-F05138.svg)](https://swift.org/package-manager/)

# PostHog iOS

Please see the main [PostHog docs](https://posthog.com/docs).

Specifically, the [iOS integration](https://posthog.com/docs/integrations/ios-integration) details.

# Development Guide

To get started

1. Install XCode
2. Install [CocoaPods](https://guides.cocoapods.org/using/getting-started.html)
3. Run `pod install`
    1. If you face segmentation faults on M1 Macs, [this might be a potential cause](https://github.com/ffi/ffi/issues/864)
    2. To fix, run `gem install --user-install ffi -- --enable-libffi-alloc`
4. Open the **file** `PostHog.xcworkspace` workspace in XCode
5. Run tests [using the test navigator](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/05-running_tests.html) . Skip TvOS tests by changing the target in the top middle bar from `PostHog` to `PostHogTests`.

## Questions?

### [Join our Slack community.](https://join.slack.com/t/posthogusers/shared_invite/enQtOTY0MzU5NjAwMDY3LTc2MWQ0OTZlNjhkODk3ZDI3NDVjMDE1YjgxY2I4ZjI4MzJhZmVmNjJkN2NmMGJmMzc2N2U3Yjc3ZjI5NGFlZDQ)
