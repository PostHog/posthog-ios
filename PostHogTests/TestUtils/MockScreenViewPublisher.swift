//
//  MockScreenViewPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

@testable import PostHog

final class MockScreenViewPublisher: ScreenViewPublishing {
    lazy var onScreenView = PostHogMulticastCallback<String>()

    private(set) var didStartAutoCapture = false
    private(set) var didStopAutoCapture = false
    private var autoCaptureHandler: ((String) -> Void)?

    func onNewScreenName(_ screenName: String) {
        onScreenView.invoke(screenName)
    }

    func startAutoCapture(_ handler: @escaping (String) -> Void) {
        autoCaptureHandler = handler
        didStartAutoCapture = true
    }

    func stopAutoCapture() {
        autoCaptureHandler = nil
        didStopAutoCapture = true
    }

    /// Drives the auto-capture path that the production `viewDidAppear`
    /// swizzle would take: calls back into the integration's handler so it
    /// can fire its own `screen()` and (transitively) update subscribers.
    func simulateAutoCapture(screen: String) {
        autoCaptureHandler?(screen)
    }

    /// Drives the passive multicast path that `PostHogSDK.screen()` invokes
    /// directly. Useful for testing read-only subscribers in isolation.
    func simulateScreenView(screen: String) {
        onScreenView.invoke(screen)
    }
}
