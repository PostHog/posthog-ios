import PostHog
import SwiftUI
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let config = PostHogConfig(
            apiKey: "_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"
        )
        config.debug = true

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.capture("Event from TvOS example!")

        return true
    }
}
