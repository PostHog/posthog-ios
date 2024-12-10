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
            apiKey: "phc_fXTO4H5ic4ntNjJk2kbAt27SAIO95imPh5ixRiLKZ6Q",
            host: "http://localhost:8000"
        )
        // the ScreenViews for SwiftUI does not work, the names are not useful
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = false
//        config.flushAt = 1
//        config.flushIntervalSeconds = 30
        config.debug = true
        config.sendFeatureFlagEvent = false
        config.sessionReplay = true
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.maskAllTextInputs = false
        config.sessionReplayConfig.maskAllImages = false

        PostHogSDK.shared.setup(config)
//        PostHogSDK.shared.debug()
//        PostHogSDK.shared.capture("App started!")
//        PostHogSDK.shared.reset()

//        PostHogSDK.shared.identify("Manoel")

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
        print("user receiveFeatureFlags callback")
    }
}
