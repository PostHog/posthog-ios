//
//  PostHogExampleWatchOSApp.swift
//  PostHogExampleWatchOS Watch App
//
//  Created by Manoel Aranda Neto on 02.11.23.
//

import PostHog
import SwiftUI

@main
struct PostHogExampleWatchOS_Watch_AppApp: App {
    init() {
        // TODO: init on app delegate instead
        let config = PostHogConfig(
            apiKey: "_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"
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
