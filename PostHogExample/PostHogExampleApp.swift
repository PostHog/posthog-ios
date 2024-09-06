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
//            ContentView()
//                .postHogScreenView() // will infer the class name (ContentView)
            VStack {
                Color.white
            }
        }
    }
}
