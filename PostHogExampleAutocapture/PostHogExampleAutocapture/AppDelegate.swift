/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The application-specific delegate class.
*/

import PostHog
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let config = PostHogConfig(
            apiKey: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = false
        config.debug = true
        config.sendFeatureFlagEvent = false
        config.sessionReplay = false
        
        PostHogSDK.shared.setup(config)
        
        return true
    }

}
