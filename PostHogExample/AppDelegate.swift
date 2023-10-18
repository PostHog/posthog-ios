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
            apiKey: "_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"
        )

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.debug()
        PostHogSDK.shared.capture("App started!")

//        DispatchQueue.global(qos: .utility).async {
//            let task = Api().failingRequest()
//        }

//        DispatchQueue.concurrentPerform(iterations: 10) { iteration in
//            PostHog.shared.capture("Parallel event", properties: [
//                "iteration": iteration
//            ])
//        }

        return true
    }
}
