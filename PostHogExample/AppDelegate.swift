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
        let config = PostHogConfig(apiKey: "_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI", host: "")
        // the ScreenViews for SwiftUI does not work, the names are not useful
        config.captureScreenViews = false
        
        let postHog = PostHogSDK.with(config)
        postHog.capture("")

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
