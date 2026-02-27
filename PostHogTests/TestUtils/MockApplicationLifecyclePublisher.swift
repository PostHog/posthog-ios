//
//  MockApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

import Foundation
@testable import PostHog

final class MockApplicationLifecyclePublisher: AppLifecyclePublishing {
    private(set) lazy var onDidBecomeActive = PostHogMulticastCallback<Void>()
    private(set) lazy var onDidEnterBackground = PostHogMulticastCallback<Void>()
    private(set) lazy var onDidFinishLaunching = PostHogMulticastCallback<Void>()

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
