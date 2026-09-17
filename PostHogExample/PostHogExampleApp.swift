//
//  PostHogExampleApp.swift
//  PostHogExample
//
//  Created by Ben White on 10.01.23.
//

import SwiftUI

@main
struct PostHogExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if NSClassFromString("XCTestCase") != nil {
                Color.clear
            } else {
                exampleContent
            }
        }
    }

    @ViewBuilder private var exampleContent: some View {
        #if DEBUG && os(iOS)
            if ProcessInfo.processInfo.environment["POSTHOG_PROTOTYPE"] == "1" {
                SwiftUITapPrototypeView()
            } else {
                normalContent
            }
        #else
            normalContent
        #endif
    }

    private var normalContent: some View {
        ContentView()
            .postHogScreenView() // will infer the class name (ContentView)
            .postHogDeepLinkListener()
            .overlay(alignment: .topTrailing) {
                FPSCounterView()
            }
    }
}
