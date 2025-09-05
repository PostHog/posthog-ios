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
            apiKey: "phc_WKfvDfedaJEDCoUmt9pVa3OWtbbUP1W2ctxwXkt3A3n"
        )
        // the ScreenViews for SwiftUI does not work, the names are not useful
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = false
//        config.flushAt = 1
//        config.flushIntervalSeconds = 30
        config.debug = false
        config.sendFeatureFlagEvent = false

        #if os(iOS)
            config.sessionReplay = true
            config.sessionReplayConfig.screenshotMode = true
            config.sessionReplayConfig.maskAllTextInputs = true
            config.sessionReplayConfig.maskAllImages = true
            config.sessionReplayConfig.captureLogs = true
            config.sessionReplayConfig.captureLogsConfig.minLogLevel = .info
            config.sessionReplayConfig.captureLogsConfig.logSanitizer = { log in
                // Skip some logs
                guard !log.contains("[SKIP]") else { return nil }
                // all logs are lowercased and info level
                return PostHogLogEntry(level: .info, message: log.lowercased())
            }
        #endif

        PostHogSDK.shared.setup(config)
//        PostHogSDK.shared.debug()
//        PostHogSDK.shared.capture("App started!")
//        PostHogSDK.shared.reset()

//        PostHogSDK.shared.identify("Manoel")

        let defaultCenter = NotificationCenter.default

        #if os(iOS) || os(tvOS) || os(visionOS)
            defaultCenter.addObserver(self,
                                      selector: #selector(receiveFeatureFlags),
                                      name: PostHogSDK.didReceiveFeatureFlags,
                                      object: nil)
        #endif

        return true
    }

    @objc func receiveFeatureFlags() {
        print("user receiveFeatureFlags callback")
        print("[SKIP] user receiveFeatureFlags callback")
    }
}
