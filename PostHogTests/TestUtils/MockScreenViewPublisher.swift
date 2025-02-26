//
//  MockScreenViewPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

@testable import PostHog

final class MockScreenViewPublisher: BaseScreenViewPublisher {
    func simulateScreenView(screen: String) {
        notifyHandlers(screen: screen)
    }
}
