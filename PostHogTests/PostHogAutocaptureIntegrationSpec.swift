//
//  PostHogAutocaptureIntegrationSpec.swift
//  PostHog
//
//  Created by Yiannis Josephides on 31/10/2024.
//

import Foundation
@testable import PostHog
import Testing

#if os(iOS)
    @Suite("PostHogAutocaptureIntegration", .serialized, .resetsGlobalState)
    final class PostHogAutocaptureIntegrationSpec {
        private let server: MockPostHogServer
        private let integration: PostHogAutocaptureIntegration
        private let posthog: PostHogSDK

        init() throws {
            deleteSafely(applicationSupportDirectoryURL())

            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.captureElementInteractions = true
            config.flushIntervalSeconds = 0.2
            config.maxBatchSize = 1
            config.disableFlushOnBackgroundForTesting = true

            server = MockPostHogServer()
            server.start()

            posthog = PostHogSDK.with(config)

            integration = try #require(posthog.getAutocaptureIntegration())
            integration.start()
        }

        deinit {
            server.stop()
            integration.stop()
            posthog.endSession()
            posthog.close()
            deleteSafely(applicationSupportDirectoryURL())
        }

        // MARK: - when initialized

        @Test("should set the eventProcessor to itself on start")
        func setsEventProcessorOnStart() {
            integration.start()
            #expect(PostHogAutocaptureEventTracker.eventProcessor === integration)
        }

        @Test("should clear the eventProcessor on stop")
        func clearsEventProcessorOnStop() {
            integration.start()
            integration.stop()
            #expect(PostHogAutocaptureEventTracker.eventProcessor == nil)
        }

        // MARK: - processing events

        @Test("should process events without a debounce interval")
        func processesEventsWithoutDebounce() {
            let event = createTestEventData()
            server.start(batchCount: 2)

            integration.process(source: .actionMethod(description: "buttonPress"), event: event)
            integration.process(source: .actionMethod(description: "buttonPress"), event: event)

            let events = getBatchedEvents(server)

            #expect(events.count == 2)
        }

        @Test("should process events from different sources")
        func processesEventsFromDifferentSources() {
            let event = createTestEventData()

            server.start(batchCount: 3)

            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .gestureRecognizer(description: "gesture1"), event: event)

            let events = getBatchedEvents(server)

            #expect(events.count == 3)
        }

        @Test("should debounce events if debounceInterval is greater than 0")
        func debouncesEvents() {
            let debouncedEvent = createTestEventData(debounceInterval: 0.2)

            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)

            posthog.flush()

            let debouncedEvents = getBatchedEvents(server)

            #expect(debouncedEvents.count == 1)

            server.start(batchCount: 6)
            let event = createTestEventData()
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)

            posthog.flush()

            let events = getBatchedEvents(server)

            #expect(events.count == 6)
        }
    }

    // Helper function to create test event data
    private func createTestEventData(debounceInterval: TimeInterval = 0) -> PostHogAutocaptureEventTracker.EventData {
        PostHogAutocaptureEventTracker.EventData(
            touchCoordinates: nil,
            value: nil,
            screenName: "TestScreen",
            viewHierarchy: [
                .init(
                    text: "Test Button",
                    targetClass: "UIButton",
                    baseClass: "UIControl",
                    label: nil
                ),
            ],
            debounceInterval: debounceInterval
        )
    }
#endif
