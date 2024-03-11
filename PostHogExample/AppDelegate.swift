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
            apiKey: "phc_pQ70jJhZKHRvDIL5ruOErnPy6xiAiWCqlL4ayELj4X8"
        )
        // the ScreenViews for SwiftUI does not work, the names are not useful
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = false
        config.flushAt = 1
        config.flushIntervalSeconds = 10
        config.debug = true
        config.sendFeatureFlagEvent = false
        config.sessionReplay = true

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.debug()

        var width: Float = 0
        var height: Float = 0
        #if os(iOS) || os(tvOS)
            width = Float(UIScreen.main.bounds.width)
            height = Float(UIScreen.main.bounds.height)
        #elseif os(macOS)
            if let mainScreen = NSScreen.main {
                width = Float(screenFrame.size.width)
                height = Float(screenFrame.size.height)
            }
        #endif

        let timestamp = Int(Date().timeIntervalSince1970.rounded())
        let data: [String: Any] = ["href": "AppDelegate", "width": width, "height": height]
        let snapshotData: [String: Any] = ["type": 4, "data": data, "timestamp": 1_710_173_534_407]
        PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotData])

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
