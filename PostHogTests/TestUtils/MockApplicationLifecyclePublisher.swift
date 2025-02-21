//
//  MockApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

@testable import PostHog

final class MockApplicationLifecyclePublisher: BaseApplicationLifecyclePublisher {
    func simulateAppDidEnterBackground() {
        didEnterBackgroundCallbacks.values.forEach { $0() }
    }

    func simulateAppDidBecomeActive() {
        didBecomeActiveCallbacks.values.forEach { $0() }
    }

    func simulateAppDidFinishLaunching() {
        didFinishLaunchingCallbacks.values.forEach { $0() }
    }
}
