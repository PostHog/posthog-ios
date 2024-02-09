//
//  AppDelegate.swift
//  PostHogExample
//
//  Created by Ben White on 10.01.23.
//

import Foundation
import PostHog
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let config = PostHogConfig(
            apiKey: "phc_qG6IuV0jr9X2UqJvwSttW3ic2xICSqTXT4q40Aw5Mlb",
            host: "https://euuuu.posthog.com"
        )
        // the ScreenViews for SwiftUI does not work, the names are not useful
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = false
        config.flushAt = 1
        config.flushIntervalSeconds = 10
        config.debug = true

        PostHogSDK.shared.setup(config)
//        PostHogSDK.shared.debug()
//        PostHogSDK.shared.capture("App started!")

        let defaultCenter = NotificationCenter.default

        #if os(iOS) || os(tvOS)
            defaultCenter.addObserver(self,
                                      selector: #selector(receiveFeatureFlags),
                                      name: PostHogSDK.didReceiveFeatureFlags,
                                      object: nil)
        #endif

        return true
    }

    @objc func receiveFeatureFlags() {
        print("receiveFeatureFlags")
    }
}
