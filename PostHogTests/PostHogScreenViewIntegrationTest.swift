//
//  PostHogScreenViewIntegrationTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 21/02/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Screen view integration tests", .serialized)
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
        // Unique token per test → isolated on-disk queue so events from a
        // previous test (or previous `swift test` invocation) can't load
        // into this SDK and skew event counts.
        let token = "screenview_test_\(UUID().uuidString)"
        let config = PostHogConfig(projectToken: token, host: "https://localhost:9090")
        config.captureScreenViews = captureScreenViews
        config.captureApplicationLifecycleEvents = false
        config.flushAt = 1
        config.disableFlushOnBackgroundForTesting = true
        config.disableReachabilityForTesting = true

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    @Test("captures $screen event when a screen appears")
    func capturesScreenEvent() async throws {
        let sut = getSut()

        // Drives the auto-capture path the swizzle would take in production:
        // the publisher calls into the integration's handler, which calls
        // postHog.screen() and emits the $screen event.
        mockScreenView.simulateAutoCapture(screen: "Test Screen")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events[0].event == "$screen")
        #expect(events[0].properties["$screen_name"] as? String == "Test Screen")

        sut.close()
    }

    @Test("respects configuration and does not capture $screen event")
    func respectsConfigurationAndDoesNotCaptureScreenEvent() async throws {
        let sut = getSut(captureScreenViews: false)

        // Integration is not installed in this config, so its handler is
        // never registered with the publisher; simulating an auto-capture is
        // a no-op. We send a satisfy event to confirm the queue still works.
        mockScreenView.simulateAutoCapture(screen: "Test Screen")
        sut.capture("Satisfy Queue")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events[0].event == "Satisfy Queue")

        sut.close()
    }

    @Test("integration registers and unregisters its auto-capture handler with the publisher")
    func integrationOwnsAutoCaptureLifecycle() async throws {
        // Install path: when captureScreenViews is true, the integration must
        // have called startAutoCapture during its own install() so the
        // publisher is wired up to receive viewDidAppear events.
        let sut = getSut(captureScreenViews: true)
        #expect(mockScreenView.didStartAutoCapture)
        #expect(!mockScreenView.didStopAutoCapture)

        // Tear-down path: closing the SDK should uninstall the integration,
        // which in turn stops the auto-capture so the swizzle deactivates.
        sut.close()
        #expect(mockScreenView.didStopAutoCapture)
    }

    @Test("manual screen() call is broadcast to subscribers")
    func manualScreenInvokesSubscribers() async throws {
        // The whole point of routing PostHogSDK.screen() through the publisher
        // is so passive subscribers (e.g. PostHogLogger.lastScreenName) see
        // the latest user-meaningful name — including when SwiftUI's
        // .postHogScreenView modifier is the only source.
        let sut = getSut(captureScreenViews: false)

        var observed: [String] = []
        let token = mockScreenView.onScreenView.subscribe { name in
            observed.append(name)
        }
        defer { _ = token }

        sut.screen("ManualScreen")

        // Subscriber callback runs synchronously inside screen(), so by the
        // time we return we should have one observation.
        #expect(observed == ["ManualScreen"])

        sut.close()
    }

    @Test("captureScreenViews=false + manual screen() updates the logger's lastScreenName")
    func loggerLastScreenNamePopulatedFromManualScreen() async throws {
        // End-to-end: with auto-capture disabled (no integration installed),
        // a manual screen() call (or the SwiftUI .postHogScreenView modifier
        // which routes through it) must still feed the logs feature's
        // screen.name attribute. This is the regression that motivated
        // option-3 unification.
        let sut = getSut(captureScreenViews: false)
        let logger = try #require(sut.logger)

        sut.screen("HomeScreen")

        // The logger's screen-view subscription updates synchronously inside
        // the publisher invocation, so it's safe to read immediately.
        #expect(logger.lastScreenName == "HomeScreen")

        // A second call should overwrite the cache, not append.
        sut.screen("DetailsScreen")
        #expect(logger.lastScreenName == "DetailsScreen")

        sut.close()
    }
}
