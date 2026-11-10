import Combine
import Foundation
@testable import PostHog
import Testing

@Suite("Survey cancel events", .serialized)
struct PostHogSurveyCancelEventsTest {
    private func makeIntegration() throws -> (PostHogSDK, PostHogSurveyIntegration) {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.disableRemoteConfigForTesting = true
        config.flushAt = 1
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        PostHogStorage(config).reset()
        let postHog = PostHogSDK.with(config)
        PostHogSurveyIntegration.clearInstalls()
        let integration = PostHogSurveyIntegration()
        let installResult = integration.install(postHog)
        try #require(installResult == .installed)
        integration.stop()
        return (postHog, integration)
    }

    private func load(_ integration: PostHogSurveyIntegration) {
        let survey: [String: Any] = [
            "id": "cancel-survey",
            "name": "Cancel survey",
            "type": "popover",
            "questions": [[
                "id": "q",
                "type": "open",
                "question": "How was checkout?",
            ]],
            "conditions": [
                "events": ["values": [["name": "show_survey"]]],
                "cancel_events": ["values": [["name": "checkout_completed"]]],
            ],
            "start_date": "2024-01-01T00:00:00.000Z",
        ]
        integration.decodeAndSetSurveys(remoteConfig: ["surveys": [survey]]) { _ in }
    }

    @Test("a cancel event drops an activation that has not been shown")
    func cancelClearsActivation() throws {
        let (postHog, integration) = try makeIntegration()
        defer {
            postHog.close()
            postHog.reset()
        }
        load(integration)
        let placeholder = try #require(integration.decodeSurveys(from: [
            "surveys": [[
                "id": "placeholder",
                "name": "Placeholder",
                "type": "popover",
                "questions": [["id": "p", "type": "open", "question": "Hold"]],
                "start_date": "2024-01-01T00:00:00.000Z",
            ]],
        ]).first)
        integration.setShownSurvey(placeholder)

        integration.testOnEvent(event: PostHogEvent(event: "show_survey", distinctId: "user", properties: [:], timestamp: Date()))
        #expect(integration.testIsEventActivated(surveyId: "cancel-survey"))

        integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))
        #expect(!integration.testIsEventActivated(surveyId: "cancel-survey"))
    }

    @Test("a cancel event dismisses a survey that is already on screen")
    func cancelDismissesShownSurvey() throws {
        let (postHog, integration) = try makeIntegration()
        defer {
            postHog.close()
            postHog.reset()
        }
        var events: [PostHogEvent] = []
        let dismissed = DispatchSemaphore(value: 0)
        postHog.config.setBeforeSend { event in
            events.append(event)
            if event.event == "survey dismissed" {
                dismissed.signal()
            }
            return nil
        }
        load(integration)
        let survey = try #require(integration.decodeSurveys(from: [
            "surveys": [[
                "id": "cancel-survey",
                "name": "Cancel survey",
                "type": "popover",
                "questions": [[
                    "id": "q",
                    "type": "open",
                    "question": "How was checkout?",
                ]],
                "conditions": [
                    "events": ["values": [["name": "show_survey"]]],
                    "cancel_events": ["values": [["name": "checkout_completed"]]],
                ],
                "start_date": "2024-01-01T00:00:00.000Z",
            ]],
        ]).first)
        integration.setShownSurvey(survey)
        integration.testSurveyCallbacks().shown(survey.toDisplaySurvey())

        integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))

        #expect(dismissed.wait(timeout: .now() + 2) == .success)
        #expect(events.contains { $0.event == "survey dismissed" })
        #expect(integration.canShowNextSurvey())
    }

    #if os(iOS)
        @Test("a cancel event captured off the main thread dismisses survey UI on main")
        func backgroundCancellation() throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            load(integration)
            let survey = try #require(integration.decodeSurveys(from: [
                "surveys": [[
                    "id": "cancel-survey",
                    "name": "Cancel survey",
                    "type": "popover",
                    "questions": [[
                        "id": "q",
                        "type": "open",
                        "question": "How was checkout?",
                    ]],
                    "conditions": [
                        "events": ["values": [["name": "show_survey"]]],
                        "cancel_events": ["values": [["name": "checkout_completed"]]],
                    ],
                    "start_date": "2024-01-01T00:00:00.000Z",
                ]],
            ]).first)
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)
            controller.showSurvey(survey.toDisplaySurvey())
            integration.setShownSurvey(survey)
            integration.testSurveyCallbacks().shown(survey.toDisplaySurvey())

            let dismissedOnMain = Locked(false)
            let finished = DispatchSemaphore(value: 0)
            let subscription = controller.$displayedSurvey.dropFirst().sink { _ in
                dismissedOnMain.withLock { $0 = Thread.isMainThread }
                finished.signal()
            }
            defer { subscription.cancel() }

            DispatchQueue.global(qos: .userInitiated).async {
                integration.testOnEvent(event: PostHogEvent(
                    event: "checkout_completed",
                    distinctId: "user",
                    properties: [:],
                    timestamp: Date()
                ))
            }

            #expect(finished.wait(timeout: .now() + 2) == .success)
            #expect(dismissedOnMain.withLock { $0 })
            #expect(controller.displayedSurvey == nil)
        }

        @Test("a background cancel returns without waiting for main")
        func captureMustNotWaitForMain() throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            load(integration)
            let survey = try #require(survey(id: "cancel-survey", integration: integration))
            integration.setShownSurvey(survey)
            integration.testSurveyCallbacks().shown(survey.toDisplaySurvey())

            let mainHeld = DispatchSemaphore(value: 0)
            let releaseMain = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                mainHeld.signal()
                _ = releaseMain.wait(timeout: .now() + 5)
            }
            #expect(mainHeld.wait(timeout: .now() + 2) == .success)

            let returned = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                integration.testOnEvent(event: PostHogEvent(
                    event: "checkout_completed",
                    distinctId: "user",
                    properties: [:],
                    timestamp: Date()
                ))
                returned.signal()
            }
            #expect(returned.wait(timeout: .now() + 1) == .success)
            releaseMain.signal()
        }

        @Test("a queued cancel does not clear a survey reserved after reset")
        func staleCancellationAfterReset() throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            load(integration)
            let original = try #require(survey(id: "cancel-survey", integration: integration))
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)

            for replacementId in ["other-survey", "cancel-survey"] {
                integration.setShownSurvey(original)
                let mainHeld = DispatchSemaphore(value: 0)
                let releaseMain = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    mainHeld.signal()
                    _ = releaseMain.wait(timeout: .now() + 5)
                }
                #expect(mainHeld.wait(timeout: .now() + 2) == .success)

                let queued = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    integration.testOnEvent(event: PostHogEvent(
                        event: "checkout_completed",
                        distinctId: "user",
                        properties: [:],
                        timestamp: Date()
                    ))
                    queued.signal()
                }
                #expect(queued.wait(timeout: .now() + 1) == .success)
                let replacement = try #require(survey(id: replacementId, integration: integration, delay: 0.2))
                integration.setShownSurvey(replacement)
                let submissionId = integration.testActiveSubmissionId
                if replacementId == "cancel-survey" {
                    delegate.renderSurvey(
                        replacement.toDisplaySurvey(),
                        onSurveyShown: { _ in },
                        onSurveyResponse: { _, _, _ in nil },
                        onSurveyClosed: { _ in }
                    )
                    #expect(controller.displayedSurvey == nil)
                }

                releaseMain.signal()
                DispatchQueue.main.sync {}
                #expect(integration.testActiveSubmissionId == submissionId)
                #expect(!integration.canShowNextSurvey())

                if replacementId == "cancel-survey" {
                    let shown = DispatchSemaphore(value: 0)
                    let subscription = controller.$displayedSurvey.dropFirst().sink { survey in
                        if survey != nil { shown.signal() }
                    }
                    #expect(shown.wait(timeout: .now() + 2) == .success)
                    subscription.cancel()
                    #expect(controller.displayedSurvey?.id == "cancel-survey")
                    controller.dismissSurvey()
                }
            }
        }

        private func survey(id: String, integration: PostHogSurveyIntegration, delay: TimeInterval? = nil) -> PostHogSurvey? {
            var body: [String: Any] = [
                "id": id,
                "name": "Cancel survey",
                "type": "popover",
                "questions": [[
                    "id": "q",
                    "type": "open",
                    "question": "How was checkout?",
                ]],
                "conditions": [
                    "events": ["values": [["name": "show_survey"]]],
                    "cancel_events": ["values": [["name": "checkout_completed"]]],
                ],
                "start_date": "2024-01-01T00:00:00.000Z",
            ]
            if let delay {
                body["appearance"] = ["surveyPopupDelaySeconds": delay]
            }
            return integration.decodeSurveys(from: ["surveys": [body]]).first
        }
    #endif
}

#if os(iOS)
    private final class Locked<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func withLock<T>(_ body: (inout Value) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }
#endif
