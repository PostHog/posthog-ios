//
//  PostHogRageClickIntegrationTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/04/2025.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Rage click integration tests", .serialized)
    struct PostHogRageClickIntegrationTests {
        private func setupPostHog(
            captureElementInteractions: Bool = true,
            captureRageClicks: Bool = true
        ) -> (MockPostHogServer, PostHogSDK, PostHogRageClickIntegration?) {
            let config = PostHogConfig(projectToken: testAPIKey, host: "http://localhost:9001")
            config.captureElementInteractions = captureElementInteractions
            config.rageClickConfig.enabled = captureRageClicks
            config.rageClickConfig.minimumTapCount = 3
            config.rageClickConfig.thresholdPoints = 30
            config.rageClickConfig.timeoutInterval = 1.0
            config.flushIntervalSeconds = 0.2
            config.maxBatchSize = 1
            config.disableFlushOnBackgroundForTesting = true

            let server = MockPostHogServer()
            server.start()

            let posthog = PostHogSDK.with(config)
            let integration = posthog.getRageClickIntegration()
            integration?.start()

            return (server, posthog, integration)
        }

        private func teardown(
            server: MockPostHogServer,
            posthog: PostHogSDK,
            integration: PostHogRageClickIntegration?
        ) {
            server.stop()
            integration?.stop()
            posthog.endSession()
            posthog.close()
            deleteSafely(applicationSupportDirectoryURL())
        }

        @Test("Emits $rageclick event after 3 rapid taps in the same area")
        func emitsRageClickAfterRapidTaps() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(x: 100, y: 200)
            try #require(integration).processTapForTesting(x: 105, y: 205)
            try #require(integration).processTapForTesting(x: 102, y: 202)

            let events = getBatchedEvents(server)
            let autocaptureEvents = events.filter { $0.event == "$autocapture" }
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(autocaptureEvents.count == 0)
            #expect(rageclickEvents.count == 1)
        }

        @Test("Does not emit $rageclick when taps are too far apart")
        func noRageClickWhenTooFarApart() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 0)

            try #require(integration).processTapForTesting(x: 0, y: 0)
            try #require(integration).processTapForTesting(x: 100, y: 100)
            try #require(integration).processTapForTesting(x: 200, y: 200)

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 0)
        }

        @Test("Emits $rageclick when element interactions are disabled")
        func emitsRageClickWhenElementInteractionsDisabled() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: false, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(x: 100, y: 200)
            try #require(integration).processTapForTesting(x: 105, y: 205)
            try #require(integration).processTapForTesting(x: 102, y: 202)

            let events = getBatchedEvents(server)
            let autocaptureEvents = events.filter { $0.event == "$autocapture" }
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(autocaptureEvents.count == 0)
            #expect(rageclickEvents.count == 1)
        }

        @Test("Does not install rage click integration when captureRageClicks is disabled")
        func doesNotInstallWhenDisabled() {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: false)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            #expect(integration == nil)
        }

        @Test("Does not emit $rageclick without screenName unless element id is present")
        func noRageClickWithoutScreenNameAndElementId() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 0)

            try #require(integration).processTapForTesting(x: 100, y: 200, screenName: nil, elementsChain: "UIButton:attr__class=\"UIButton\"")
            try #require(integration).processTapForTesting(x: 105, y: 205, screenName: nil, elementsChain: "UIButton:attr__class=\"UIButton\"")
            try #require(integration).processTapForTesting(x: 102, y: 202, screenName: nil, elementsChain: "UIButton:attr__class=\"UIButton\"")

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 0)
        }

        @Test("Emits $rageclick without screenName when element id is present")
        func rageClickWithoutScreenNameWithElementId() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(x: 100, y: 200, screenName: nil, elementsChain: "UIButton:attr_id=\"retry-button\"")
            try #require(integration).processTapForTesting(x: 105, y: 205, screenName: nil, elementsChain: "UIButton:attr_id=\"retry-button\"")
            try #require(integration).processTapForTesting(x: 102, y: 202, screenName: nil, elementsChain: "UIButton:attr_id=\"retry-button\"")

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 1)
        }

        @Test("Emits $rageclick when screenName exists even if elementsChain is empty")
        func rageClickWithScreenNameAndNoElementsChain() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(x: 100, y: 200, screenName: "TestScreen", elementsChain: "")
            try #require(integration).processTapForTesting(x: 105, y: 205, screenName: "TestScreen", elementsChain: "")
            try #require(integration).processTapForTesting(x: 102, y: 202, screenName: "TestScreen", elementsChain: "")

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 1)
        }

        @Test("$rageclick event carries expected properties")
        func rageClickEventHasExpectedProperties() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(x: 100, y: 200)
            try #require(integration).processTapForTesting(x: 105, y: 205)
            try #require(integration).processTapForTesting(x: 102, y: 202)

            let events = getBatchedEvents(server)
            let rageclickEvent = try #require(events.first(where: { $0.event == "$rageclick" }))

            #expect(rageclickEvent.properties["$event_type"] as? String == "touch")
            #expect(rageclickEvent.properties["$touch_x"] != nil)
            #expect(rageclickEvent.properties["$touch_y"] != nil)
            #expect(rageclickEvent.properties["$screen_name"] as? String == "TestScreen")
        }
    }
#endif
