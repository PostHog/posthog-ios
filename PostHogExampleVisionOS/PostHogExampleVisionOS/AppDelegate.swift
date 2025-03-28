//
//  AppDelegate.swift
//  PostHogExampleVisionOS
//
//  Created by Ioannis Josephides on 19/03/2025.
//

import PostHog
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let config = PostHogConfig(
            apiKey: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )
        config.debug = true

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.capture("Event from VisionOS example!")

        return true
    }
}
