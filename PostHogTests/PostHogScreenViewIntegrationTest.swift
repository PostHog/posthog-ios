//
//  PostHogScreenViewIntegrationTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

import Testing

@testable import PostHog

@Suite("Screen view integration tests")
final class ScreenViewIntegrationTest {
    var server: MockPostHogServer!
    let mockScreenView = MockScreenViewPublisher()

    init() {
        PostHogScreenViewIntegration.clearInstalls()

        server = MockPostHogServer()
        server.start()
        DI.main.screenViewPublisher = mockScreenView
    }

    deinit {
        server.stop()
        server = nil
        DI.main.screenViewPublisher = ApplicationScreenViewPublisher.shared
    }

    private func getSut(captureScreenViews: Bool = true) -> PostHogSDK {
        let config = PostHogConfig(apiKey: "test", host: "https://localhost:9000")
        config.captureScreenViews = captureScreenViews
        config.flushAt = 1

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    @Test("captures $screen event when a screen appears")
    func capturesScreenEvent() async throws {
        let sut = getSut()

        mockScreenView.simulateScreenView(screen: "Test Screen")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events[0].event == "$screen")
        #expect(events[0].properties["$screen_name"] as? String == "Test Screen")

        sut.close()
    }

    @Test("respects configuration and does not capture $screen event")
    func respectsConfigurationAndDoesNotCaptureScreenEvent() async throws {
        let sut = getSut(captureScreenViews: false)

        mockScreenView.simulateScreenView(screen: "Test Screen")
        sut.capture("Satisfy Queue")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events[0].event == "Satisfy Queue")

        sut.close()
    }
}
