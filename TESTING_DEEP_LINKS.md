# Testing Deep Link Capture

This document outlines how to use and verify the deep link capture feature.

> **Note:** Deep link capture is no longer automatic via swizzling. You must manually call `captureDeepLink` or use the SwiftUI modifier.

## 1. Integration

### SwiftUI Apps

Attach the `.postHogDeepLinkHandler()` modifier to your root view (e.g., `ContentView` or your main `WindowGroup` scene).

```swift
import SwiftUI
import PostHog

@main
struct MyApp: App {
    init() {
        // Setup PostHog
        let config = PostHogConfig(apiKey: "API_KEY")
        PostHogSDK.shared.setup(config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .postHogDeepLinkHandler() // Capture deep links automatically
        }
    }
}
```

### UIKit (AppDelegate/SceneDelegate)

Call `PostHogSDK.shared.captureDeepLink` manually in your delegate methods.

**AppDelegate:**

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    let referrer = options[.sourceApplication] as? String
    PostHogSDK.shared.captureDeepLink(url: url, referrer: referrer)
    return true
}

func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
        PostHogSDK.shared.captureDeepLink(url: url, referrer: userActivity.referrerURL?.absoluteString)
    }
    return true
}
```

**SceneDelegate:**

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
        let referrer = context.options.sourceApplication
        PostHogSDK.shared.captureDeepLink(url: context.url, referrer: referrer)
    }
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
        PostHogSDK.shared.captureDeepLink(url: url, referrer: userActivity.referrerURL?.absoluteString)
    }
}
```

## 2. Verification

### Scenario A: Custom URL Scheme via Terminal (Simulator)
1.  Build and run the app on the iOS Simulator.
2.  Background the app.
3.  Open Terminal and run:
    ```bash
    xcrun simctl openurl booted "my-app://path/to/content?foo=bar"
    ```
4.  **Verification:**
    - Watch the Xcode console logs (if `config.debug = true`).
    - Verify `Deep Link Opened` event in PostHog.
    - **Properties:** `url` should be `my-app://path/to/content?foo=bar`.

### Scenario B: Universal Link via Safari
1.  Install the app on a device or simulator.
2.  Open Safari.
3.  Navigate to a supported URL (e.g., `https://your-site.com/link`).
4.  Open in App.
5.  **Verification:**
    - Verify `Deep Link Opened` event.
    - **Properties:** `$referrer` should be the Safari URL (if available).

### Scenario C: App-to-App Referrer
1.  Open a link to your app from another app (e.g., Messages).
2.  **Verification:**
    - Verify `Deep Link Opened` event.
    - **Properties:** `$referrer` should be the bundle ID (e.g., `com.apple.MobileSMS`).
