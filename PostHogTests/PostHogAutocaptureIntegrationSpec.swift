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
    @Suite("PostHogAutocaptureIntegration Tests", .serialized)
    class PostHogAutocaptureIntegrationSpec {
        let server: MockPostHogServer
        var integration: PostHogAutocaptureIntegration!
        var posthog: PostHogSDK!
        let apiKey: String

        init() {
            apiKey = uniqueApiKey()
            server = MockPostHogServer()
            server.start()

            let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
            config.captureElementInteractions = true
            config.flushIntervalSeconds = 0.2
            config.maxBatchSize = 1

            posthog = PostHogSDK.with(config)
            integration = posthog.getAutocaptureIntegration()
            integration.start()
        }

        deinit {
            server.stop()
            integration.stop()
            posthog.endSession()
            posthog.close()
            deleteSafely(applicationSupportDirectoryURL())
        }

        @Suite("when initialized")
        struct WhenInitialized {
            @Test("should set the eventProcessor to itself on start")
            func shouldSetEventProcessorToItselfOnStart() {
                let apiKey = uniqueApiKey()
                let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
                config.captureElementInteractions = true
                let posthog = PostHogSDK.with(config)
                let integration = posthog.getAutocaptureIntegration()

                integration?.start()
                #expect(PostHogAutocaptureEventTracker.eventProcessor === integration)

                integration?.stop()
                posthog.close()
            }

            @Test("should clear the eventProcessor on stop")
            func shouldClearEventProcessorOnStop() {
                let apiKey = uniqueApiKey()
                let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
                config.captureElementInteractions = true
                let posthog = PostHogSDK.with(config)
                let integration = posthog.getAutocaptureIntegration()

                integration?.start()
                integration?.stop()
                #expect(PostHogAutocaptureEventTracker.eventProcessor == nil)

                posthog.close()
            }
        }

        @Test("should process an event")
        func shouldProcessAnEvent() async throws {
            let event = createTestEventData()
            integration.process(source: .actionMethod(description: "buttonPress"), event: event)
            integration.process(source: .actionMethod(description: "buttonPress"), event: event)

            let events = try await getServerEvents(server)

            #expect(events.count == 1)
        }

        @Test("should respect shouldProcess based on configuration")
        func shouldRespectShouldProcessBasedOnConfiguration() async throws {
            let event = createTestEventData()

            server.start(batchCount: 2)

            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .actionMethod(description: "action"), event: event)
            integration.process(source: .gestureRecognizer(description: "gesture1"), event: event)

            let events = try await getServerEvents(server)

            #expect(events.count == 2)
        }

        @Test("should debounce events if debounceInterval is greater than 0")
        func shouldDebounceEventsIfDebounceIntervalIsGreaterThan0() async throws {
            let debouncedEvent = createTestEventData(debounceInterval: 0.2)

            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
            integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)

            posthog.flush()

            let debouncedEvents = try await getServerEvents(server)

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

            let events = try await getServerEvents(server)

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
