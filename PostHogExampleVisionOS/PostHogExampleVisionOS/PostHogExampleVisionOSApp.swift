//
//  PostHogExampleVisionOSApp.swift
//  PostHogExampleVisionOS
//
//  Created by Ioannis Josephides on 19/03/2025.
//

import PostHog
import SwiftUI

@main
struct PostHogExampleVisionOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
