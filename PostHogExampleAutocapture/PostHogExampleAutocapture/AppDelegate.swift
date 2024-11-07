/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 The application-specific delegate class.
 */

import PostHog
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let config = PostHogConfig(
            apiKey: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )
        config.debug = true

        config.captureElementInteractions = true
        config.captureApplicationLifecycleEvents = true
        config.sendFeatureFlagEvent = false

        config.sessionReplay = true
        config.captureScreenViews = true
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.maskAllTextInputs = false
        config.sessionReplayConfig.maskAllImages = false

        PostHogSDK.shared.setup(config)
        
        PostHogSDK.shared.identify("Max Capture")
        
        return true
    }
}
