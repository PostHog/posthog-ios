import Foundation
@testable import PostHog
import Testing

@Suite("Survey cancel events", .serialized)
final class PostHogSurveyCancelEventsTest {
    private let server = MockPostHogServer()

    init() {
        server.start()
    }

    deinit {
        server.stop()
    }

    private func makeIntegration() throws -> (PostHogSDK, PostHogSurveyIntegration) {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.disableRemoteConfigForTesting = true
        config.preloadFeatureFlags = false
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

    @discardableResult
    private func load(_ integration: PostHogSurveyIntegration, id: String = "cancel-survey", delay: Double = 0) throws -> PostHogSurvey {
        let survey: [String: Any] = [
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
            "appearance": ["surveyPopupDelaySeconds": delay],
            "start_date": "2024-01-01T00:00:00.000Z",
        ]
        var surveys: [PostHogSurvey] = []
        integration.decodeAndSetSurveys(remoteConfig: ["surveys": [survey]]) { surveys = $0 }
        return try #require(surveys.first)
    }

    @Test("a cancel event drops an activation that has not been shown")
    func cancelClearsActivation() throws {
        let (postHog, integration) = try makeIntegration()
        defer {
            postHog.close()
            postHog.reset()
        }
        try load(integration)
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

    @Test("cancellation preserves an attempt owned by a custom delegate", arguments: [false, true], ["checkout_completed", "unrelated"])
    @MainActor
    func customDelegateKeepsOwnership(shownBeforeCancel: Bool, eventName: String) async throws {
        let (postHog, integration) = try makeIntegration()
        defer {
            postHog.close()
            postHog.reset()
        }
        let delegate = RecordingSurveyDelegate()
        postHog.config._surveysConfig.surveysDelegate = delegate
        let survey = try load(integration)
        let nextSurvey = try #require(integration.decodeSurveys(from: ["surveys": [[
            "id": "next-survey", "name": "Next survey", "type": "popover",
            "questions": [["id": "next", "type": "open", "question": "Next?"]],
            "start_date": "2024-01-01T00:00:00.000Z",
        ]]]).first)
        integration.setSurveys([survey, nextSurvey])
        var events: [String] = []
        postHog.config.setBeforeSend { event in
            events.append(event.event)
            return nil
        }
        integration.setShownSurvey(survey)
        let callbacks = integration.testSurveyCallbacks()
        delegate.renderSurvey(survey.toDisplaySurvey(), onSurveyShown: callbacks.shown, onSurveyResponse: callbacks.response, onSurveyClosed: callbacks.closed)
        let presentation = try #require(delegate.presentations.first)
        let submissionId = try #require(integration.testActiveSubmissionId)
        if shownBeforeCancel {
            presentation.callbacks.shown(presentation.survey)
        }

        integration.testOnEvent(event: PostHogEvent(event: eventName, distinctId: "user", properties: [:], timestamp: Date()))
        await drainDisplayQueue()

        #expect(integration.testActiveSubmissionId == submissionId)
        #expect(!integration.canShowNextSurvey())
        #expect(!events.contains("survey dismissed"))
        #if os(iOS)
            integration.hasActiveSurveyWindow = { true }
            integration.showNextSurvey()
            await drainDisplayQueue()
            #expect(delegate.presentations.count == 1)
        #endif
        if !shownBeforeCancel {
            presentation.callbacks.shown(presentation.survey)
        }
        #expect(events.filter { $0 == "survey shown" }.count == 1)
        let next = presentation.callbacks.response(presentation.survey, 0, .openEnded("Answer"))
        #expect(next?.isSurveyCompleted == true)
        #expect(events.filter { $0 == "survey sent" }.count == 1)
        #expect(!events.contains("survey dismissed"))
        presentation.callbacks.closed(presentation.survey)
        #expect(integration.canShowNextSurvey())
    }

    @MainActor
    private func drainDisplayQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    #if os(iOS)
        @Test("cancel events preserve a visible built-in survey", arguments: [false, true], [false, true])
        @MainActor
        func cancelKeepsShownSurvey(background: Bool, answer: Bool) async throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            let survey = try load(integration)
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)
            var events: [String] = []
            postHog.config.setBeforeSend { event in
                events.append(event.event)
                return nil
            }
            integration.setShownSurvey(survey)
            let submissionId = try #require(integration.testActiveSubmissionId)
            let callbacks = integration.testSurveyCallbacks()
            delegate.renderSurvey(survey.toDisplaySurvey(), onSurveyShown: callbacks.shown, onSurveyResponse: callbacks.response, onSurveyClosed: callbacks.closed)

            if background {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))
                        continuation.resume()
                    }
                }
            } else {
                integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))
            }
            await drainDisplayQueue()

            #expect(controller.displayedSurvey?.id == survey.id)
            #expect(integration.testActiveSubmissionId == submissionId)
            #expect(!integration.canShowNextSurvey())
            #expect(events == ["survey shown"])
            if answer {
                controller.onNextQuestion(index: 0, response: .openEnded("Answer"))
                #expect(controller.isSurveyCompleted)
                #expect(events.filter { $0 == "survey sent" }.count == 1)
            }
            controller.dismissSurvey()
            #expect(events.filter { $0 == "survey dismissed" }.count == (answer ? 0 : 1))
            #expect(integration.canShowNextSurvey())
        }

        @Test("cancel events preserve answers before the shown callback")
        @MainActor
        func responseThenCancellation() throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            let delegate = RecordingSurveyDelegate()
            postHog.config._surveysConfig.surveysDelegate = delegate
            try load(integration)
            let survey = try #require(integration.decodeSurveys(from: ["surveys": [[
                "id": "cancel-survey", "name": "Cancel survey", "type": "popover",
                "questions": [
                    ["id": "first", "type": "open", "question": "First?"],
                    ["id": "second", "type": "open", "question": "Second?"],
                ],
                "start_date": "2024-01-01T00:00:00.000Z",
            ]]]).first)
            var events: [PostHogEvent] = []
            postHog.config.setBeforeSend { event in
                events.append(event)
                return nil
            }
            integration.setShownSurvey(survey)
            let callbacks = integration.testSurveyCallbacks()
            delegate.renderSurvey(survey.toDisplaySurvey(), onSurveyShown: callbacks.shown, onSurveyResponse: callbacks.response, onSurveyClosed: callbacks.closed)
            let presentation = try #require(delegate.presentations.first)
            let next = try #require(presentation.callbacks.response(presentation.survey, 0, .openEnded("Answer")))
            #expect(!next.isSurveyCompleted)

            integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))

            #expect(!events.contains { $0.event == "survey dismissed" })
            #expect(!integration.canShowNextSurvey())
            let completed = presentation.callbacks.response(presentation.survey, 1, .openEnded("Second answer"))
            #expect(completed?.isSurveyCompleted == true)
            let sent = try #require(events.first { $0.event == "survey sent" })
            #expect(sent.properties["$survey_response_first"] as? String == "Answer")
            #expect(sent.properties["$survey_response_second"] as? String == "Second answer")
            presentation.callbacks.closed(presentation.survey)
            #expect(integration.canShowNextSurvey())
        }

        @Test("a background cancellation capture returns while the main queue is busy")
        @MainActor
        func captureMustNotWaitForMain() async throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                integration.stop()
                postHog.close()
                postHog.reset()
            }
            let survey = try load(integration, delay: 60)
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)
            integration.setShownSurvey(survey)
            let callbacks = integration.testSurveyCallbacks()
            delegate.renderSurvey(survey.toDisplaySurvey(), onSurveyShown: callbacks.shown, onSurveyResponse: callbacks.response, onSurveyClosed: callbacks.closed)
            integration.start()
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                postHog.capture("checkout_completed")
                finished.signal()
            }

            #expect(finished.wait(timeout: .now() + 1) == .success)
            #expect(!integration.canShowNextSurvey())
            await drainDisplayQueue()
            #expect(integration.canShowNextSurvey())
            #expect(controller.displayedSurvey == nil)
        }

        @Test("a stale cancellation cannot clear a new attempt after reset", arguments: [false, true])
        @MainActor
        func staleCancellationAfterReset(sameId: Bool) async throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            let survey = try load(integration, delay: 60)
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)
            integration.setShownSurvey(survey)
            let callbacks = integration.testSurveyCallbacks()
            delegate.renderSurvey(survey.toDisplaySurvey(), onSurveyShown: callbacks.shown, onSurveyResponse: callbacks.response, onSurveyClosed: callbacks.closed)

            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "old-user", properties: [:], timestamp: Date()))
                finished.signal()
            }
            _ = finished.wait(timeout: .now() + 1)
            postHog.reset()
            integration.cancelPendingSurvey()
            let replacement = try load(integration, id: sameId ? survey.id : "replacement", delay: 60)
            integration.setShownSurvey(replacement)
            let replacementSubmissionId = try #require(integration.testActiveSubmissionId)
            let replacementCallbacks = integration.testSurveyCallbacks()
            delegate.renderSurvey(replacement.toDisplaySurvey(), onSurveyShown: replacementCallbacks.shown, onSurveyResponse: replacementCallbacks.response, onSurveyClosed: replacementCallbacks.closed)

            await drainDisplayQueue()

            #expect(integration.testActiveSubmissionId == replacementSubmissionId)
            #expect(delegate.cancelPendingSurveyIfPresented(replacement.id))
        }

        @Test("cancelling a pending display releases it without interaction events")
        @MainActor
        func cancelPendingDisplay() throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                postHog.close()
                postHog.reset()
            }
            let survey = try load(integration, delay: 60)
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)
            var events: [String] = []
            postHog.config.setBeforeSend { event in
                events.append(event.event)
                return nil
            }
            integration.setShownSurvey(survey)
            let callbacks = integration.testSurveyCallbacks()
            delegate.renderSurvey(survey.toDisplaySurvey(), onSurveyShown: callbacks.shown, onSurveyResponse: callbacks.response, onSurveyClosed: callbacks.closed)

            integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))

            #expect(integration.canShowNextSurvey())
            #expect(events.isEmpty)
            #expect(!delegate.cancelPendingSurveyIfPresented(survey.id))
        }

        @Test("a cancellation between selection and reservation suppresses display")
        @MainActor
        func cancelBeforeReservation() async throws {
            let (postHog, integration) = try makeIntegration()
            defer {
                integration.stop()
                postHog.close()
                postHog.reset()
            }
            try load(integration)
            integration.hasActiveSurveyWindow = { true }
            let delegate = try #require(postHog.config._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate)
            let controller = SurveyDisplayController()
            delegate.setDisplayControllerForTesting(controller)
            integration.start()
            postHog.capture("show_survey")
            DispatchQueue.main.async { postHog.capture("checkout_completed") }

            await drainDisplayQueue()

            #expect(controller.displayedSurvey == nil)
            #expect(integration.canShowNextSurvey())
        }

    #endif
}

private final class RecordingSurveyDelegate: NSObject, PostHogSurveysDelegate {
    var presentations: [(survey: PostHogDisplaySurvey, callbacks: SurveyCallbacks)] = []

    func renderSurvey(
        _ survey: PostHogDisplaySurvey,
        onSurveyShown: @escaping OnPostHogSurveyShown,
        onSurveyResponse: @escaping OnPostHogSurveyResponse,
        onSurveyClosed: @escaping OnPostHogSurveyClosed
    ) {
        presentations.append((survey, SurveyCallbacks(shown: onSurveyShown, response: onSurveyResponse, closed: onSurveyClosed)))
    }

    func cleanupSurveys() {}
}
