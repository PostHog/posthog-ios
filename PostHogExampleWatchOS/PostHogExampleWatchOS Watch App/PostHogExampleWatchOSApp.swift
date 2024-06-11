//
//  PostHogExampleWatchOSApp.swift
//  PostHogExampleWatchOS Watch App
//
//  Created by Manoel Aranda Neto on 02.11.23.
//

import PostHog
import SwiftUI

@main
struct PostHogExampleWatchOSApp: App {
    init() {
        // TODO: init on app delegate instead
        let config = PostHogConfig(
            apiKey: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.debug()
        PostHogSDK.shared.capture("Event from WatchOS example!")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
