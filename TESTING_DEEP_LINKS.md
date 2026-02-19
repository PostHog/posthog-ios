# Testing Deep Link Capture

This document outlines how to verify that the automatic deep link capture feature works as expected.

## 1. Unit Testing

Since the feature relies on swizzling `UIApplicationDelegate` and `UISceneDelegate`, unit tests need to ensure that the integration installs correctly and that the tracking logic produces the correct events.

### Example Test Case (Swift)

You can add a test case to `PostHogTests` to verify the property extraction logic.

```swift
import XCTest
@testable import PostHog

class PostHogDeepLinkTests: XCTestCase {

    func testTrackDeepLinkWithReferrer() {
        // Setup
        let config = PostHogConfig(apiKey: "test_api_key")
        config.captureDeepLinks = true
        let postHog = PostHogSDK.with(config)

        // Mock URL and Referrer
        let url = URL(string: "https://myapp.com/product/123?utm_source=newsletter")!
        let referrer = "https://www.google.com"

        // Trigger tracking manually (since we can't easily mock the swizzling in a simple unit test without a host app)
        // Note: internal access to PostHogDeepLinkIntegration might be needed or test via the public side effect
        PostHogDeepLinkIntegration.trackDeepLink(url: url, referrer: referrer)

        // Verify (Mocking the Queue/Network would be required for a real assertion)
        // Check logs or use a mock server to verify "Deep Link Opened" event was sent
        // Properties should include:
        // - url: "https://myapp.com/product/123?utm_source=newsletter"
        // - $referrer: "https://www.google.com"
        // - $referring_domain: "www.google.com"
    }
}
