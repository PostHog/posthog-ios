//
//  AppDelegate.swift
//  PostHogExampleWithPods
//
//  Created by Manoel Aranda Neto on 24.10.23.
//

import Foundation
import PostHog
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let defaultCenter = NotificationCenter.default

        defaultCenter.addObserver(self,
                                  selector: #selector(self.receiveFeatureFlags),
                                  name: PostHogSDK.didReceiveFeatureFlags,
                                  object: nil)

        let config = PostHogConfig(
            apiKey: "_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"
        )

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.debug()
        PostHogSDK.shared.capture("Event from CocoaPods example!")

        return true
    }

    @objc func receiveFeatureFlags() {
        print("receiveFeatureFlags")
    }
}
