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

    // MARK: - PostHogScreenNameSanitizer

    @Test("sanitize: pure UIKit class names pass through unchanged")
    func sanitizePassesUIKitNames() {
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: "MyHomeViewController") == "MyHomeViewController")
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: "SettingsVC") == "SettingsVC")
    }

    @Test("sanitize: UIHostingController<X> → X")
    func sanitizeStripsHostingController() {
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: "UIHostingController<HomeView>") == "HomeView")
    }

    @Test("sanitize: ModifiedContent<X, _> → X (peels one modifier)")
    func sanitizePeelsOneModifier() {
        let raw = "UIHostingController<ModifiedContent<DetailView, EnvironmentValueWriter>>"
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: raw) == "DetailView")
    }

    @Test("sanitize: nested ModifiedContent recurses to innermost user view")
    func sanitizeRecursesNestedModifiers() {
        // `WindowGroup { ContentView().padding().background(...) }` produces
        // a left-leaning ModifiedContent chain like this — the user's view
        // is at the innermost left.
        let raw = "UIHostingController<ModifiedContent<ModifiedContent<HomeView, A>, B>>"
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: raw) == "HomeView")
    }

    @Test("sanitize: AnyView surfaced from stripping returns nil")
    func sanitizeReturnsNilForAnyViewFromStripping() {
        // The exact shape we observed end-to-end in PostHogExample.
        let raw = "UIHostingController<ModifiedContent<AnyView, RootModifier>>"
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: raw) == nil)
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: "UIHostingController<AnyView>") == nil)
    }

    @Test("sanitize: literal AnyView passes through (caller intent)")
    func sanitizeKeepsLiteralAnyView() {
        // A caller who typed `screen("AnyView")` deliberately gets that
        // name through; only the auto-capture noise case is dropped.
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: "AnyView") == "AnyView")
    }

    @Test("sanitize: empty / whitespace-only returns nil")
    func sanitizeReturnsNilForEmpty() {
        #expect(PostHogScreenNameSanitizer.sanitize(rawScreenName: "") == nil)
    }

    @Test("screen() with degenerate input preserves the previous useful name")
    func screenWithDegenerateInputPreservesLastUsefulName() async throws {
        // SwiftUI initial layout often emits multiple viewDidAppears: a
        // useful one (e.g. ContentView) followed by AnyView-wrapped ones
        // from container chrome. SDK.screen() sanitizes; degenerate inputs
        // must not erase the good name we already had.
        let sut = getSut(captureScreenViews: false)

        sut.screen("HomeView")
        #expect(sut.lastScreenName == "HomeView")

        sut.screen("UIHostingController<ModifiedContent<AnyView, RootModifier>>")
        #expect(sut.lastScreenName == "HomeView")

        sut.close()
    }

    @Test("captureScreenViews=false + manual screen() seeds the SDK cache")
    func screenCachePopulatedFromManualCall() async throws {
        // End-to-end: with auto-capture disabled (no integration installed),
        // a manual screen() call (or the SwiftUI .postHogScreenView modifier
        // which routes through it) must still feed the SDK's screen-name
        // cache so the logs feature and cross-event stamping pick it up.
        let sut = getSut(captureScreenViews: false)

        sut.screen("HomeScreen")
        #expect(sut.lastScreenName == "HomeScreen")

        // A second call should overwrite the cache, not append.
        sut.screen("DetailsScreen")
        #expect(sut.lastScreenName == "DetailsScreen")

        sut.close()
    }
}
