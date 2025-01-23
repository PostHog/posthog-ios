//
//  MockApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/01/2025.
//

import Foundation
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
