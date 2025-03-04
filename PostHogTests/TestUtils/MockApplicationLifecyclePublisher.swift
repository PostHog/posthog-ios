//
//  MockApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

@testable import PostHog

final class MockApplicationLifecyclePublisher: BaseApplicationLifecyclePublisher {
    func simulateAppDidEnterBackground() {
        didEnterBackgroundHandlers.forEach { $0() }
    }

    func simulateAppDidBecomeActive() {
        didBecomeActiveHandlers.forEach { $0() }
    }

    func simulateAppDidFinishLaunching() {
        didFinishLaunchingHandlers.forEach { $0() }
    }
}
