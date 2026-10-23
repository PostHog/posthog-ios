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
        PostHogSDK.shared.onFeatureFlags { [weak self] _ in
            self?.receiveFeatureFlags()
        }

        let config = PostHogConfig(
            projectToken: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.debug()
        PostHogSDK.shared.capture("Event from SPM example!")

        return true
    }

    func receiveFeatureFlags() {
        print("receiveFeatureFlags")
    }
}
