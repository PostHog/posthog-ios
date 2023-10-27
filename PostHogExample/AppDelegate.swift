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
//        PostHogSDK.shared.debug()
//        let props: [String : Any] = ["test": 1,
//                                     "test2": 2.1,
//                                     "test3": "test",
//                                     "test4": true,
//                                     "test5": [1, 2, 3],
//                                     "test6": ["one": 1]]
        let defaultCenter = NotificationCenter.default
        let props: [String: Any] = ["not": defaultCenter, "url": URL(string: "123")!]
        PostHogSDK.shared.capture("App started!", properties: props)

//        DispatchQueue.global(qos: .utility).async {
//            let task = Api().failingRequest()
//        }

//        DispatchQueue.concurrentPerform(iterations: 10) { iteration in
//            PostHog.shared.capture("Parallel event", properties: [
//                "iteration": iteration
//            ])
//        }

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
