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

    /// Override platform snapshots independently of the simulated notification history.
    var isInBackground: Bool = false
    var isActive: Bool = false
    private var hasObservedActivation = false
    var hasBecomeActive: Bool {
        if Thread.isMainThread, isActive {
            hasObservedActivation = true
        }
        return hasObservedActivation
    }

    func simulateAppDidEnterBackground() {
        onDidEnterBackground.invoke(())
    }

    func simulateAppDidBecomeActive() {
        hasObservedActivation = true
        onDidBecomeActive.invoke(())
    }

    func simulateAppDidFinishLaunching() {
        onDidFinishLaunching.invoke(())
    }
}
