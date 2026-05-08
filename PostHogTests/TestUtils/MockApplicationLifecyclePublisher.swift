//
//  MockApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

import Foundation
@testable import PostHog

final class MockApplicationLifecyclePublisher: AppLifecyclePublishing {
    let onDidBecomeActive = PostHogMulticastCallback<Void>()
    let onDidEnterBackground = PostHogMulticastCallback<Void>()
    let onDidFinishLaunching = PostHogMulticastCallback<Void>()

    /// Override per-test to simulate the app being in foreground or
    /// background at the moment some consumer queries the publisher.
    var isInBackground: Bool = false

    func simulateAppDidEnterBackground() {
        onDidEnterBackground.invoke(())
    }

    func simulateAppDidBecomeActive() {
        onDidBecomeActive.invoke(())
    }

    func simulateAppDidFinishLaunching() {
        onDidFinishLaunching.invoke(())
    }
}
