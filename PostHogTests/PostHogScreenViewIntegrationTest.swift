//
//  PostHogScreenViewIntegrationTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

@testable import PostHog
import Testing

@Suite("Screen view integration tests", .serialized)
final class ScreenViewIntegrationTest: PostHogSDKBaseTest {
    let mockScreenView = MockScreenViewPublisher()

    init() {
        super.init()
        PostHogScreenViewIntegration.clearInstalls()
        DI.main.screenViewPublisher = mockScreenView
    }

    deinit {
        DI.main.screenViewPublisher = ApplicationScreenViewPublisher.shared
    }

    private func getSut(captureScreenViews: Bool = true) -> PostHogSDK {
        let config = makeConfig(host: "https://localhost:9090")
        config.captureScreenViews = captureScreenViews
        config.flushAt = 1
        return makeSDK(config: config)
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
