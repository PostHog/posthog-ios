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
```

## 2. Manual Testing (Simulator or Device)

To verify the integration end-to-end:

### Prerequisites
1.  Use an iOS app that integrates the PostHog SDK.
2.  Ensure `config.captureDeepLinks = true` (default).
3.  Configure a Custom URL Scheme (e.g., `my-app://`) or Universal Links for your app.

### Scenario A: Custom URL Scheme via Terminal (Simulator)
1.  Build and run the app on the iOS Simulator.
2.  Background the app.
3.  Open Terminal and run:
    ```bash
    xcrun simctl openurl booted "my-app://path/to/content?foo=bar"
    ```
4.  **Verification:**
    - Watch the Xcode console logs (if debug logging is enabled via `config.debug = true`).
    - You should see a log entry for capturing `Deep Link Opened`.
    - Check the event in PostHog Activity:
        - **Event:** `Deep Link Opened`
        - **Property `url`:** `my-app://path/to/content?foo=bar`
        - **Property `$referrer`:** (Might be nil or system defined depending on source)

### Scenario B: Universal Link via Safari
1.  Install the app on a device or simulator.
2.  Open Safari.
3.  Navigate to a URL that your app supports (e.g., `https://your-site.com/link`).
4.  Tap "Open in [App Name]" banner or if it redirects automatically.
5.  **Verification:**
    - **Event:** `Deep Link Opened`
    - **Property `url`:** `https://your-site.com/link`
    - **Property `$referrer`:** URL of the page you were on in Safari.
    - **Property `$referring_domain`:** Domain of the referrer.

### Scenario C: App-to-App Referrer
1.  Create a second test app or use Notes/Messages.
2.  Paste your custom URL scheme link `my-app://test`.
3.  Tap the link to open your app.
4.  **Verification:**
    - **Event:** `Deep Link Opened`
    - **Property `$referrer`:** Bundle ID of the calling app (e.g., `com.apple.mobilenotes`).

## 3. Verify Configuration Toggle
1.  Set `config.captureDeepLinks = false` in your initialization code.
2.  Repeat Scenario A.
3.  **Verification:** Ensure **NO** `Deep Link Opened` event is captured.
