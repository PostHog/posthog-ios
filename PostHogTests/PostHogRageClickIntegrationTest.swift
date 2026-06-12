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
    import UIKit

    @Suite("Rage click integration tests", .serialized)
    struct PostHogRageClickIntegrationTests {
        private func setupPostHog(
            captureElementInteractions: Bool = true,
            captureRageClicks: Bool = true
        ) -> (MockPostHogServer, PostHogSDK, PostHogRageClickIntegration?) {
            // Reset the process-wide install flag so a prior test can't leave it "already installed".
            PostHogRageClickIntegration.clearInstalls()

            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
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

            try #require(integration).processTapForTesting(touchX: 100, touchY: 200)
            try #require(integration).processTapForTesting(touchX: 105, touchY: 205)
            try #require(integration).processTapForTesting(touchX: 102, touchY: 202)

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

            try #require(integration).processTapForTesting(touchX: 0, touchY: 0)
            try #require(integration).processTapForTesting(touchX: 100, touchY: 100)
            try #require(integration).processTapForTesting(touchX: 200, touchY: 200)

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 0)
        }

        @Test("Emits $rageclick when element interactions are disabled")
        func emitsRageClickWhenElementInteractionsDisabled() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: false, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(touchX: 100, touchY: 200)
            try #require(integration).processTapForTesting(touchX: 105, touchY: 205)
            try #require(integration).processTapForTesting(touchX: 102, touchY: 202)

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

            try #require(integration).processTapForTesting(touchX: 100, touchY: 200, screenName: nil, elementsChain: "UIButton:attr__class=\"UIButton\"")
            try #require(integration).processTapForTesting(touchX: 105, touchY: 205, screenName: nil, elementsChain: "UIButton:attr__class=\"UIButton\"")
            try #require(integration).processTapForTesting(touchX: 102, touchY: 202, screenName: nil, elementsChain: "UIButton:attr__class=\"UIButton\"")

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 0)
        }

        @Test("Emits $rageclick without screenName when element id is present")
        func rageClickWithoutScreenNameWithElementId() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(touchX: 100, touchY: 200, screenName: nil, elementsChain: "UIButton:attr_id=\"retry-button\"", elementLabel: "retry-button")
            try #require(integration).processTapForTesting(touchX: 105, touchY: 205, screenName: nil, elementsChain: "UIButton:attr_id=\"retry-button\"", elementLabel: "retry-button")
            try #require(integration).processTapForTesting(touchX: 102, touchY: 202, screenName: nil, elementsChain: "UIButton:attr_id=\"retry-button\"", elementLabel: "retry-button")

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 1)
        }

        @Test("Emits $rageclick when screenName exists even if elementsChain is empty")
        func rageClickWithScreenNameAndNoElementsChain() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(touchX: 100, touchY: 200, screenName: "TestScreen", elementsChain: "")
            try #require(integration).processTapForTesting(touchX: 105, touchY: 205, screenName: "TestScreen", elementsChain: "")
            try #require(integration).processTapForTesting(touchX: 102, touchY: 202, screenName: "TestScreen", elementsChain: "")

            let events = getBatchedEvents(server)
            let rageclickEvents = events.filter { $0.event == "$rageclick" }

            #expect(rageclickEvents.count == 1)
        }

        @Test("$rageclick event carries expected properties")
        func rageClickEventHasExpectedProperties() throws {
            let (server, posthog, integration) = setupPostHog(captureElementInteractions: true, captureRageClicks: true)
            defer { teardown(server: server, posthog: posthog, integration: integration) }

            server.start(batchCount: 1)

            try #require(integration).processTapForTesting(touchX: 100, touchY: 200)
            try #require(integration).processTapForTesting(touchX: 105, touchY: 205)
            try #require(integration).processTapForTesting(touchX: 102, touchY: 202)

            let events = getBatchedEvents(server)
            let rageclickEvent = try #require(events.first(where: { $0.event == "$rageclick" }))

            #expect(rageclickEvent.properties["$event_type"] as? String == "touch")
            #expect(rageclickEvent.properties["$touch_x"] != nil)
            #expect(rageclickEvent.properties["$touch_y"] != nil)
            #expect(rageclickEvent.properties["$screen_name"] as? String == "TestScreen")
        }

        // MARK: - Suppression on ineligible elements

        // These assert the suppression decision directly, avoiding the async capture/flush pipeline.

        @MainActor
        @Test("Taps on the on-screen keyboard window are ineligible for rage clicks")
        func keyboardWindowIsIneligible() {
            let integration = PostHogRageClickIntegration()
            #expect(integration.isRageClickIneligibleForTesting(view: UIView(), isKeyboardWindow: true))
        }

        /// Controls where rapid repeated taps are intentional, as a `Sendable` enum so the test
        /// below can be parameterised (UIViews aren't `Sendable`).
        enum IntentionalControl: String, CaseIterable {
            case textField, textView, searchBar, stepper, slider, datePicker, pickerView, segmentedControl, pageControl

            @MainActor
            func makeView() -> UIView {
                switch self {
                case .textField: return UITextField()
                case .textView: return UITextView()
                case .searchBar: return UISearchBar()
                case .stepper: return UIStepper()
                case .slider: return UISlider()
                case .datePicker: return UIDatePicker()
                case .pickerView: return UIPickerView()
                case .segmentedControl: return UISegmentedControl(items: ["a", "b"])
                case .pageControl: return UIPageControl()
                }
            }
        }

        @MainActor
        @Test("Controls where rapid taps are intentional are ineligible for rage clicks", arguments: IntentionalControl.allCases)
        func intentionalControlIsIneligible(_ control: IntentionalControl) {
            let integration = PostHogRageClickIntegration()
            #expect(integration.isRageClickIneligibleForTesting(view: control.makeView()), "\(control.rawValue) should be ineligible")
        }

        @MainActor
        @Test("A view nested inside an ineligible control is also ineligible")
        func subviewOfIneligibleControlIsIneligible() {
            let integration = PostHogRageClickIntegration()
            let textField = UITextField()
            let innerView = UIView()
            textField.addSubview(innerView)

            #expect(integration.isRageClickIneligibleForTesting(view: innerView))
        }

        @MainActor
        @Test("A view marked with the ph-no-rageclick accessibility identifier is ineligible")
        func viewMarkedByAccessibilityIdentifierIsIneligible() {
            let integration = PostHogRageClickIntegration()
            let view = UIView()
            view.accessibilityIdentifier = "checkout-quantity ph-no-rageclick"

            #expect(integration.isRageClickIneligibleForTesting(view: view))
        }

        @MainActor
        @Test("A view marked with the ph-no-rageclick accessibility label is ineligible")
        func viewMarkedByAccessibilityLabelIsIneligible() {
            let integration = PostHogRageClickIntegration()
            let view = UIView()
            view.accessibilityLabel = "ph-no-rageclick"

            #expect(integration.isRageClickIneligibleForTesting(view: view))
        }

        @MainActor
        @Test("A view marked via the postHogNoRageClick flag is ineligible")
        func viewMarkedByFlagIsIneligible() {
            let integration = PostHogRageClickIntegration()
            let view = UIView()
            view.postHogNoRageClick = true

            #expect(integration.isRageClickIneligibleForTesting(view: view))
        }

        @MainActor
        @Test("A plain eligible view (e.g. a button) is not suppressed")
        func plainViewIsEligible() {
            let integration = PostHogRageClickIntegration()
            #expect(integration.isRageClickIneligibleForTesting(view: UIButton()) == false)
            #expect(integration.isRageClickIneligibleForTesting(view: UIView()) == false)
            #expect(integration.isRageClickIneligibleForTesting(view: nil) == false)
        }
    }
#endif
