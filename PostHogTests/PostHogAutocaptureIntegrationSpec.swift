//
//  PostHogAutocaptureIntegrationSpec.swift
//  PostHog
//
//  Created by Yiannis Josephides on 31/10/2024.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

#if os(iOS)
    class PostHogAutocaptureIntegrationSpec: QuickSpec {
        override func spec() {
            var server: MockPostHogServer!
            var integration: PostHogAutocaptureIntegration!
            var posthog: PostHogSDK!

            beforeEach {
                let config = PostHogConfig(apiKey: "123", host: "http://localhost:9001")
                config.captureElementInteractions = true
                config.flushIntervalSeconds = 0.2
                config.maxBatchSize = 1

                server = MockPostHogServer()
                server.start()

                posthog = PostHogSDK.with(config)

                integration = posthog.getAutocaptureIntegration()
                integration.start()
            }

            afterEach {
                server.stop()
                server = nil
                integration.stop()
                PostHogSessionManager.shared.endSession {}
                posthog.close()
                deleteSafely(applicationSupportDirectoryURL())
            }

            context("when initialized") {
                it("should set the eventProcessor to itself on start") {
                    integration.start()
                    expect(PostHogAutocaptureEventTracker.eventProcessor).to(beIdenticalTo(integration))
                }

                it("should clear the eventProcessor on stop") {
                    integration.start()
                    integration.stop()
                    expect(PostHogAutocaptureEventTracker.eventProcessor).to(beNil())
                }
            }

            context("processing events") {
                it("should process an event") {
                    let event = createTestEventData()
                    integration.process(source: .actionMethod(description: "buttonPress"), event: event)
                    integration.process(source: .actionMethod(description: "buttonPress"), event: event)

                    let events = getBatchedEvents(server)

                    expect(events.count).to(equal(1))
                }

                it("should respect shouldProcess based on configuration") {
                    let event = createTestEventData()

                    server.start(batchCount: 2)

                    integration.process(source: .actionMethod(description: "action"), event: event)
                    integration.process(source: .actionMethod(description: "action"), event: event)
                    integration.process(source: .gestureRecognizer(description: "gesture1"), event: event)

                    let events = getBatchedEvents(server)

                    expect(events.count).to(equal(2))
                }

                it("should debounce events if debounceInterval is greater than 0") {
                    let debouncedEvent = createTestEventData(debounceInterval: 0.2)

                    integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
                    integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
                    integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
                    integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
                    integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)
                    integration.process(source: .actionMethod(description: "action"), event: debouncedEvent)

                    posthog.flush()

                    let debouncedEvents = getBatchedEvents(server)

                    expect(debouncedEvents.count).to(equal(1))

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

                    expect(events.count).to(equal(6))
                }
            }
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
