[![Build](https://img.shields.io/github/actions/workflow/status/PostHog/posthog-ios/build.yml?branch=main)](https://github.com/PostHog/posthog-ios/actions/workflows/build.yml?query=branch%3Amain)
[![SwiftPM compatible](https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager)
[![Swift Package Index platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FPostHog%2Fposthog-ios%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/PostHog/posthog-ios)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FPostHog%2Fposthog-ios%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/PostHog/posthog-ios)

# PostHog iOS

Upgrading from 3.x? See the [migration guide](MIGRATION.md).

Please see the main [PostHog docs](https://posthog.com/docs).

Specifically, the [iOS docs](https://posthog.com/docs/libraries/ios) details.

## Installation

Install PostHog with [Swift Package Manager](https://www.swift.org/documentation/package-manager/). In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/PostHog/posthog-ios`, or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0")
]
```

### Moving from CocoaPods

PostHog 4.0 and later is only published to Swift Package Manager. Versions 3.x stay on CocoaPods, but no new versions will be pushed there: [CocoaPods trunk becomes read-only on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/).

To move an app from CocoaPods, remove `pod 'PostHog'` from your `Podfile`, run `pod install`, then add the package as shown above.

React Native and Flutter apps get this SDK through their PostHog package; follow that package's installation docs instead.

## Questions?

### [Check out our community page.](https://posthog.com/posts)
