//
//  MockScreenViewPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

@testable import PostHog

final class MockScreenViewPublisher: ScreenViewPublishing {
    lazy var onScreenView = PostHogMulticastCallback<String>()

    func simulateScreenView(screen: String) {
        onScreenView.invoke(screen)
    }
}
