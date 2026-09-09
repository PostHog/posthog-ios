//
//  PostHogSurveyEventsTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 03/10/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Test Survey Events", .serialized)
class PostHogSurveyEventsTest {
    let server: MockPostHogServer

    init() {
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
    }

    var defaultQuestions: [PostHogSurveyQuestion] = [
        .open(PostHogOpenSurveyQuestion(
            id: "qID1",
            question: "What do you think about our product?",
            description: "Please share your thoughts",
            descriptionContentType: .text,
            optional: false,
            buttonText: nil,
            originalQuestionIndex: 0,
            branching: nil,
            translations: nil
        )),
        .singleChoice(PostHogMultipleSurveyQuestion(
            id: "qID2",
            question: "How likely are you to recommend us?",
            description: "Please select one option",
            descriptionContentType: .text,
            optional: false,
            buttonText: nil,
            originalQuestionIndex: 1,
            branching: nil,
            translations: nil,
            choices: ["Very likely", "Somewhat likely", "Not likely"],
            hasOpenChoice: false,
            shuffleOptions: false
        )),
        .rating(PostHogRatingSurveyQuestion(
            id: "qID3",
            question: "Rate your experience",
            description: "1 = Poor, 5 = Excellent",
            descriptionContentType: .text,
            optional: false,
            buttonText: nil,
            originalQuestionIndex: 2,
            branching: nil,
            translations: nil,
            display: .number,
            scale: .fivePoint,
            lowerBoundLabel: "Poor",
            upperBoundLabel: "Excellent"
        )),
    ]

    func getTestSurvey(
        id: String = "test-survey-id",
        name: String = "Test Survey",
        questions: [PostHogSurveyQuestion],
        currentIteration: Int? = nil,
        currentIterationStartDate: Date? = nil
    ) -> PostHogSurvey {
        PostHogSurvey(
            id: id,
            name: name,
            type: .popover,
            questions: questions,
            featureFlagKeys: nil,
            linkedFlagKey: nil,
            targetingFlagKey: nil,
            internalTargetingFlagKey: nil,
            conditions: nil,
            appearance: nil,
            currentIteration: currentIteration,
            currentIterationStartDate: currentIterationStartDate,
            startDate: Date(),
            endDate: nil,
            schedule: nil,
            translations: nil
        )
    }

    func getSut(resetStorage: Bool = true) -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.disableRemoteConfigForTesting = true
        config.flushAt = 1
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false

        if resetStorage { PostHogStorage(config).reset() }
        return PostHogSDK.with(config)
    }

    func getSurveyIntegration(_ postHog: PostHogSDK) throws -> PostHogSurveyIntegration {
        PostHogSurveyIntegration.clearInstalls()
        let integration = PostHogSurveyIntegration()
        let installResult = integration.install(postHog)
        try #require(installResult == .installed)
        // These tests drive callbacks directly; remote refreshes must not replace their fixture surveys.
        integration.stop()
        return integration
    }

    func partialResponseSurvey(enabled: Bool?, branching: [String: Any]? = nil, properties: [String: Any] = [:]) throws -> PostHogSurvey {
        var first: [String: Any] = ["id": "first", "type": "open", "question": "First?", "optional": true]
        first["branching"] = branching
        var json: [String: Any] = [
            "id": "partial-survey", "name": "Partial survey", "type": "popover",
            "questions": [first, ["id": "second", "type": "open", "question": "Second?"]],
        ]
        json["enable_partial_responses"] = enabled
        json.merge(properties) { _, new in new }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PostHogSurvey.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test("resumed completion and dismissal preserve seen history", arguments: [false, true])
    func resumedSurveyPreservesSeenHistory(closeWithoutCompleting: Bool) throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        let storage = try #require(postHog.storage)
        storage.setDictionary(forKey: .surveySeen, contents: ["seenSurvey_previous": true])
        postHog.config.setBeforeSend { _ in nil }
        let survey = try partialResponseSurvey(enabled: true, properties: ["start_date": 0])
        let first = try getSurveyIntegration(postHog)
        first.setSurveys([survey])
        var matching: [PostHogSurvey] = []
        first.getActiveMatchingSurveys { matching = $0 }
        try #require(matching.count == 1)
        first.setShownSurvey(survey)
        _ = first.getNextQuestion(index: 0, response: .openEnded("Saved"))
        try #require(storage.getDictionary(forKey: .surveySeen)?["seenSurvey_previous"] as? Bool == true)
        try #require(storage.getDictionary(forKey: .surveySeen)?["seenSurvey_partial-survey"] as? Bool == true)
        first.uninstall(postHog)
        let resumed = try getSurveyIntegration(postHog)
        resumed.setSurveys([survey])
        resumed.getActiveMatchingSurveys { matching = $0 }
        try #require(matching.count == 1)
        resumed.setShownSurvey(survey)
        try #require(resumed.testActiveQuestionIndex == 1)
        if !closeWithoutCompleting {
            _ = resumed.getNextQuestion(index: 1, response: .openEnded("Final"))
        }
        resumed.testHandleSurveyClosed(survey: survey.toDisplaySurvey())
        #expect(storage.getDictionary(forKey: .surveySeen)?["seenSurvey_previous"] as? Bool == true)
        #expect(storage.getDictionary(forKey: .surveySeen)?["seenSurvey_partial-survey"] as? Bool == true)
        resumed.getActiveMatchingSurveys { matching = $0 }
        #expect(matching.isEmpty)
        resumed.uninstall(postHog)
    }

    @Test("reset invalidates an attempt before its first answer", arguments: [false, true])
    func resetBeforeFirstAnswer(keepAnonymousId: Bool) throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        postHog.config.reuseAnonymousId = keepAnonymousId
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { events.append($0)
            return nil
        }
        integration.setShownSurvey(survey)
        postHog.reset()
        #expect(integration.getNextQuestion(index: 0, response: .openEnded("Stale")) == nil)
        #expect(events.isEmpty)
        #expect(SurveyProgressStore(storage: try #require(postHog.storage)).load(survey) == nil)
        integration.uninstall(postHog)
    }

    @Test("reset in a dismissal hook preserves the new identity's attempt")
    func resetDuringDismissalPreservesNewAttempt() throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        var switchedIdentity = false
        postHog.config.setBeforeSend { event in
            if event.event == "survey dismissed", !switchedIdentity {
                switchedIdentity = true
                DispatchQueue.global().sync { postHog.reset() }
                integration.setShownSurvey(survey)
                _ = integration.getNextQuestion(index: 0, response: .openEnded("New identity"))
            }
            return nil
        }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Old identity"))
        let oldSubmission = integration.testActiveSubmissionId
        integration.testHandleSurveyClosed(survey: survey.toDisplaySurvey())
        try #require(switchedIdentity)
        let storage = try #require(postHog.storage)
        let progress = try #require(SurveyProgressStore(storage: storage).load(survey))
        #expect(progress.submissionId != oldSubmission)
        #expect(progress.responses["$survey_response_first"]?.text == "New identity")
        #expect(integration.testActiveSubmissionId == progress.submissionId)
        #expect(integration.testActiveQuestionIndex == 1)
        integration.uninstall(postHog)
    }

    @Test("callbacks from an old render cannot mutate a new attempt", arguments: [false, true])
    func staleRenderCallbacks(reset: Bool) throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        let storage = try #require(postHog.storage)
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { events.append($0)
            return nil
        }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("First render"))
        let oldCallbacks = integration.testSurveyCallbacks()
        if reset { postHog.reset() }
        integration.setShownSurvey(survey)
        if reset { _ = integration.getNextQuestion(index: 0, response: .openEnded("New identity")) }
        let submissionId = integration.testActiveSubmissionId
        let eventCount = events.count
        let display = survey.toDisplaySurvey()
        oldCallbacks.shown(display)
        #expect(oldCallbacks.response(display, 1, .openEnded("Stale response")) == nil)
        oldCallbacks.closed(display)
        #expect(events.count == eventCount)
        #expect(integration.testActiveSubmissionId == submissionId)
        let progress = try #require(SurveyProgressStore(storage: storage).load(survey))
        #expect(progress.submissionId == submissionId)
        #expect(progress.responses["$survey_response_first"]?.text == (reset ? "New identity" : "First render"))
        integration.uninstall(postHog)
    }

    @Test("SDK reset waits for a survey storage transaction")
    func resetSerializesSurveyState() throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        let storage = try #require(postHog.storage)
        let survey = try partialResponseSurvey(enabled: true, properties: ["start_date": 0])
        let integration = try getSurveyIntegration(postHog)
        postHog.config.setBeforeSend { _ in nil }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Old identity"))
        postHog.identify("identity-before-reset")
        let oldDistinctId = postHog.getDistinctId()
        let oldAnonymousId = postHog.getAnonymousId()
        let resetStarted = DispatchSemaphore(value: 0)
        let resetFinished = DispatchSemaphore(value: 0)
        let oldGeneration = storage.withSurveyState { generation in
            DispatchQueue.global().async {
                resetStarted.signal()
                postHog.reset()
                resetFinished.signal()
            }
            #expect(resetStarted.wait(timeout: .now() + 5) == .success)
            // Reset must not delete identities or progress halfway through a read-modify-write.
            #expect(resetFinished.wait(timeout: .now() + 0.05) == .timedOut)
            #expect(postHog.getDistinctId() == oldDistinctId)
            #expect(storage.getString(forKey: .distinctId) == oldDistinctId)
            #expect(postHog.getAnonymousId() == oldAnonymousId)
            #expect(storage.getString(forKey: .anonymousId) == oldAnonymousId)
            integration.updateSurveyCache([survey], events: [:])
            return generation
        }
        try #require(resetFinished.wait(timeout: .now() + 5) == .success)
        #expect(storage.withSurveyState { $0 } != oldGeneration)
        #expect(postHog.getDistinctId() != oldDistinctId)
        #expect(postHog.getAnonymousId() != oldAnonymousId)
        #expect(storage.getString(forKey: .distinctId) == nil)
        #expect(postHog.getDistinctId() == postHog.getAnonymousId())
        #expect(storage.getString(forKey: .anonymousId) == postHog.getAnonymousId())
        #expect(SurveyProgressStore(storage: storage).load(survey) == nil)
        #expect(integration.getNextQuestion(index: 1, response: .openEnded("Stale response")) == nil)
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("New identity"))
        integration.updateSurveyCache([survey], events: [:])
        #expect(SurveyProgressStore(storage: storage).load(survey)?.responses["$survey_response_first"]?.text == "New identity")
        integration.uninstall(postHog)
    }

    @Test("reset during a progress read cannot restore or remove another identity's state", arguments: ["load", "save", "remove", "reconcile"], [false, true])
    func resetDuringProgressRead(operation: String, startNewAttempt: Bool) throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        let storage = try #require(postHog.storage)
        let store = SurveyProgressStore(storage: storage)
        let survey = try partialResponseSurvey(enabled: true, properties: ["start_date": 0])
        let integration = try getSurveyIntegration(postHog)
        postHog.config.setBeforeSend { _ in nil }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Old identity"))
        let oldProgress = try #require(store.load(survey))
        storage.testOnSurveyProgressRead = {
            storage.testOnSurveyProgressRead = nil
            postHog.reset()
            if startNewAttempt {
                integration.setShownSurvey(survey)
                _ = integration.getNextQuestion(index: 0, response: .openEnded("New identity"))
            }
        }
        switch operation {
        case "load": #expect(store.load(survey) == nil)
        case "save": store.save(oldProgress, for: survey)
        case "remove": store.remove(survey)
        default: integration.updateSurveyCache([survey], events: [:])
        }
        #expect(storage.testOnSurveyProgressRead == nil)
        let progress = store.load(survey)
        if startNewAttempt {
            let progress = try #require(progress)
            #expect(progress.submissionId != oldProgress.submissionId)
            #expect(progress.responses["$survey_response_first"]?.text == "New identity")
        } else {
            #expect(progress == nil)
        }
        integration.uninstall(postHog)
    }

    @Test("reset during response validation invalidates the pending answer")
    func resetDuringResponseValidation() throws {
        let postHog = getSut()
        defer { postHog.reset()
            postHog.close()
        }
        let storage = try #require(postHog.storage)
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { events.append($0)
            return nil
        }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Old identity"))
        storage.testOnSurveyProgressRead = {
            storage.testOnSurveyProgressRead = nil
            postHog.reset()
        }
        #expect(integration.getNextQuestion(index: 1, response: .openEnded("Stale response")) == nil)
        #expect(events.count == 1)
        #expect(integration.testActiveSubmissionId == nil)
        #expect(SurveyProgressStore(storage: storage).load(survey) == nil)
        integration.uninstall(postHog)
    }

    @Test("unfinished responses survive integration restart", arguments: [true, false, nil] as [Bool?])
    func resumeAfterRestart(enabled: Bool?) throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let survey = try partialResponseSurvey(enabled: enabled)
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { events.append($0)
            return nil
        }
        let first = try getSurveyIntegration(postHog)
        first.setShownSurvey(survey)
        _ = first.getNextQuestion(index: 0, response: .openEnded("Saved answer"))
        let submissionId = first.testActiveSubmissionId
        first.uninstall(postHog)

        let resumed = try getSurveyIntegration(postHog)
        resumed.setShownSurvey(survey)
        #expect(resumed.testActiveQuestionIndex == 1)
        #expect(resumed.testActiveSubmissionId == submissionId)
        _ = resumed.getNextQuestion(index: 1, response: .openEnded("Final answer"))
        let event = try #require(events.last)
        #expect(event.properties["$survey_response_first"] as? String == "Saved answer")
        #expect(event.properties["$survey_submission_id"] as? String == submissionId)
        #expect(event.properties["$survey_completed"] as? Bool == true)
        resumed.uninstall(postHog)
        let completed = try getSurveyIntegration(postHog)
        completed.setShownSurvey(survey)
        #expect(completed.testActiveQuestionIndex == 0)
        #expect(completed.testActiveSubmissionId != submissionId)
    }

    @Test("dismissal and reset remove saved progress", arguments: [false, true])
    func clearSavedProgress(reset: Bool) throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let integration = try getSurveyIntegration(postHog)
        let survey = try partialResponseSurvey(enabled: true)
        let store = SurveyProgressStore(storage: try #require(postHog.storage))
        postHog.config.setBeforeSend { _ in nil }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        #expect(store.load(survey)?.questionIndex == 1)
        if reset {
            postHog.reset()
            #expect(integration.getNextQuestion(index: 1, response: .openEnded("Stale callback")) == nil)
        } else {
            integration.testHandleSurveyClosed(survey: survey.toDisplaySurvey())
        }
        #expect(store.load(survey) == nil)
    }

    @Test("invalid persisted progress is discarded", arguments: ["version", "questionIndex", "questionOrder", "responses"])
    func invalidSavedProgress(field: String) throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let integration = try getSurveyIntegration(postHog)
        let survey = try partialResponseSurvey(enabled: true)
        let storage = try #require(postHog.storage)
        postHog.config.setBeforeSend { _ in nil }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        var records = try #require(storage.getDictionary(forKey: .surveyProgress))
        var record = try #require(records["partial-survey/0"] as? [String: Any])
        let invalidValues: [String: Any] = [
            "version": 99, "questionIndex": 9,
            "questionOrder": ["open:second", "open:first"],
            "responses": ["first": ["type": 99]],
        ]
        record[field] = invalidValues[field]
        records["partial-survey/0"] = record
        storage.setDictionary(forKey: .surveyProgress, contents: records)
        #expect(SurveyProgressStore(storage: storage).load(survey) == nil)
        #expect(storage.getDictionary(forKey: .surveyProgress)?["partial-survey/0"] == nil)
    }

    @Test("response values survive disk round-trip", arguments: [
        PostHogSurveyResponse.rating(nil), .rating(5), .openEnded("hello"), .openEnded(nil),
        .singleChoice("A"), .multipleChoice(["A", "B"]), .multipleChoice(nil), .link(true), .link(false),
    ])
    func storedResponseRoundTrip(response: PostHogSurveyResponse) throws {
        let restored = try #require(JSONDecoder().decode(StoredSurveyResponse.self, from: JSONEncoder().encode(StoredSurveyResponse(response))).response)
        #expect(restored.type == response.type)
        #expect(restored.textValue == response.textValue)
        #expect(restored.ratingValue == response.ratingValue)
        #expect(restored.selectedOptions == response.selectedOptions)
        #expect(restored.linkClicked == response.linkClicked)
    }

    #if os(iOS)
        @Test("display controller starts at the restored question")
        @MainActor
        func restoredDisplayQuestion() throws {
            let survey = try partialResponseSurvey(enabled: true).toDisplaySurvey(initialQuestionIndex: 1)
            let controller = SurveyDisplayController()
            controller.showSurvey(survey)
            #expect(controller.currentQuestionIndex == 1)
            #expect(!controller.showingIntroScreen)
        }
        @Test("an invalidated attempt closes the displayed survey")
        @MainActor
        func invalidatedDisplayQuestion() throws {
            let survey = try partialResponseSurvey(enabled: true).toDisplaySurvey(initialQuestionIndex: 1)
            let controller = SurveyDisplayController()
            controller.onSurveyResponse = { _, _, _ in nil }
            controller.showSurvey(survey)
            controller.onNextQuestion(index: 1, response: .openEnded("Stale"))
            #expect(controller.displayedSurvey == nil)
        }
    #endif

    @Test("unfinished surveys remain eligible after partial answers mark them seen")
    func resumeEligibility() throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        postHog.config.setBeforeSend { _ in nil }
        let survey = try partialResponseSurvey(enabled: true, properties: ["start_date": 0])
        let integration = try getSurveyIntegration(postHog)
        integration.setSurveys([survey])
        var matching: [PostHogSurvey] = []
        integration.getActiveMatchingSurveys { matching = $0 }
        #expect(matching.count == 1)
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        #expect(postHog.storage?.getDictionary(forKey: .surveySeen)?["seenSurvey_partial-survey"] as? Bool == true)
        integration.uninstall(postHog)
        let resumed = try getSurveyIntegration(postHog)
        let withInternalFlag = try partialResponseSurvey(enabled: true, properties: ["start_date": 0, "internal_targeting_flag_key": "already-answered"])
        resumed.setSurveys([withInternalFlag])
        resumed.getActiveMatchingSurveys { matching = $0 }
        #expect(matching.count == 1)
        let gated = try partialResponseSurvey(enabled: true, properties: ["start_date": 0, "linked_flag_key": "disabled-product-flag"])
        resumed.setSurveys([gated])
        resumed.getActiveMatchingSurveys { matching = $0 }
        #expect(matching.isEmpty)
    }

    @Test("new iterations and ended surveys do not reuse old progress")
    func staleSurveyProgress() throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let survey = try partialResponseSurvey(enabled: true, properties: ["start_date": 0, "current_iteration": 1])
        let nextIteration = try partialResponseSurvey(enabled: true, properties: ["start_date": 0, "current_iteration": 2])
        let integration = try getSurveyIntegration(postHog)
        postHog.config.setBeforeSend { _ in nil }
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        let store = SurveyProgressStore(storage: try #require(postHog.storage))
        #expect(store.load(survey) != nil)
        #expect(store.load(nextIteration) == nil)
        store.reconcile([nextIteration])
        #expect(store.load(survey) == nil)
        integration.setShownSurvey(nextIteration)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        store.reconcile([])
        #expect(store.load(nextIteration) == nil)
    }

    @Test("restart restores the branching destination and omits skipped answers")
    func resumeBranching() throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { events.append($0)
            return nil
        }
        let survey = try partialResponseSurvey(enabled: true, properties: ["questions": [
            ["id": "first", "type": "open", "question": "First?", "branching": ["type": "specific_question", "index": 2]],
            ["id": "skipped", "type": "open", "question": "Skipped?"],
            ["id": "last", "type": "open", "question": "Last?"],
        ]])
        let first = try getSurveyIntegration(postHog)
        first.setShownSurvey(survey)
        _ = first.getNextQuestion(index: 0, response: .openEnded("Saved"))
        first.uninstall(postHog)
        let resumed = try getSurveyIntegration(postHog)
        resumed.setShownSurvey(survey)
        #expect(resumed.testActiveQuestionIndex == 2)
        _ = resumed.getNextQuestion(index: 2, response: .openEnded("Final"))
        let event = try #require(events.last)
        #expect(event.properties["$survey_response_first"] as? String == "Saved")
        #expect(event.properties["$survey_response_skipped"] == nil)
    }

    @Test("showing a survey alone does not create resumable progress")
    func noProgressBeforeAnswer() throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let integration = try getSurveyIntegration(postHog)
        let survey = try partialResponseSurvey(enabled: true)
        integration.setShownSurvey(survey)
        #expect(SurveyProgressStore(storage: try #require(postHog.storage)).load(survey) == nil)
    }

    @Test("partial responses emit cumulative answers with one submission id", arguments: [true, false, nil] as [Bool?])
    func partialResponses(enabled: Bool?) throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let integration = try getSurveyIntegration(postHog)
        let survey = try partialResponseSurvey(enabled: enabled)
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { event in
            events.append(event)
            return nil
        }

        integration.setShownSurvey(survey)
        let first = try #require(integration.getNextQuestion(index: 0, response: .openEnded("First answer")))
        #expect(!first.1)
        #expect(!integration.canShowNextSurvey())
        #expect(events.count == (enabled == true ? 1 : 0))
        if enabled == true {
            let partial = try #require(events.first)
            #expect(partial.event == "survey sent")
            #expect(partial.properties["$survey_completed"] as? Bool == false)
            #expect(partial.properties["$survey_response_first"] as? String == "First answer")
            #expect(partial.properties["$survey_response_second"] == nil)
        }

        _ = integration.getNextQuestion(index: 1, response: .openEnded("Second answer"))
        #expect(events.count == (enabled == true ? 2 : 1))
        let completed = try #require(events.last)
        #expect(completed.event == "survey sent")
        #expect(completed.properties["$survey_completed"] as? Bool == true)
        #expect(completed.properties["$survey_response_first"] as? String == "First answer")
        #expect(completed.properties["$survey_response_second"] as? String == "Second answer")
        let submissionId = try #require(completed.properties["$survey_submission_id"] as? String)
        #expect(UUID(uuidString: submissionId) != nil)
        #expect(events.allSatisfy { $0.properties["$survey_submission_id"] as? String == submissionId })
        integration.testHandleSurveyClosed(survey: survey.toDisplaySurvey())
        #expect(events.count == (enabled == true ? 2 : 1))
    }

    @Test("dismissed partial response keeps submission id and next attempt gets a new id")
    func partialResponseDismissal() throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let integration = try getSurveyIntegration(postHog)
        let survey = try partialResponseSurvey(enabled: true)
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { event in
            events.append(event)
            return nil
        }

        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        let sent = try #require(events.last)
        #expect(sent.event == "survey sent")
        let submissionId = try #require(sent.properties["$survey_submission_id"] as? String)
        integration.testHandleSurveyClosed(survey: survey.toDisplaySurvey())
        let dismissed = try #require(events.last)
        #expect(dismissed.event == "survey dismissed")
        #expect(dismissed.properties["$survey_submission_id"] as? String == submissionId)
        #expect(dismissed.properties["$survey_partially_completed"] as? Bool == true)
        #expect(dismissed.properties["$survey_response_first"] as? String == "Saved")

        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("New answer"))
        let nextId = try #require(events.last?.properties["$survey_submission_id"] as? String)
        #expect(nextId != submissionId)
        #expect(events.count == 3)
    }

    @Test("branching to end marks a partial-enabled survey complete")
    func partialResponseBranching() throws {
        let postHog = getSut()
        defer { postHog.close()
            postHog.reset()
        }
        let integration = try getSurveyIntegration(postHog)
        let survey = try partialResponseSurvey(enabled: true, branching: ["type": "end"])
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { event in
            events.append(event)
            return nil
        }
        integration.setShownSurvey(survey)
        let next = try #require(integration.getNextQuestion(index: 0, response: .openEnded(nil)))
        #expect(next.1)
        #expect(events.count == 1)
        #expect(events.first?.properties["$survey_completed"] as? Bool == true)
        #expect(events.first?.properties["$survey_response_second"] == nil)
    }

    // MARK: - Survey Shown Event Tests

    @Test("survey shown event has correct event name and properties")
    func surveyShownEventHasCorrectNameAndBaseProperties() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "survey-123",
            name: "Test Survey Name",
            questions: defaultQuestions,
            currentIteration: 2,
            currentIterationStartDate: Date(timeIntervalSince1970: 1609459200) // 2021-01-01
        )

        integration.testSendSurveyShownEvent(survey: survey)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey shown")
        #expect(event.properties["$survey_name"] as? String == "Test Survey Name")
        #expect(event.properties["$survey_id"] as? String == "survey-123")
        #expect(event.properties["$survey_iteration"] as? Int == 2)
        #expect(event.properties["$survey_iteration_start_date"] as? String == "2021-01-01T00:00:00.000Z")

        postHog.close()
        postHog.reset()
    }

    @Test("survey shown event without iteration has correct properties")
    func surveyShownEventWithoutIterationHasCorrectProperties() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "survey-id-456",
            name: "Some Simple Survey",
            questions: defaultQuestions
        )

        integration.testSendSurveyShownEvent(survey: survey)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey shown")
        #expect(event.properties["$survey_name"] as? String == "Some Simple Survey")
        #expect(event.properties["$survey_id"] as? String == "survey-id-456")
        #expect(event.properties["$survey_iteration"] == nil)
        #expect(event.properties["$survey_iteration_start_date"] == nil)

        postHog.close()
        postHog.reset()
    }

    // MARK: - Survey Sent Event Tests

    @Test("survey sent event has correct event name and response properties")
    func surveySentEventHasCorrectNameAndResponseProperties() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(questions: [
            .open(PostHogOpenSurveyQuestion(
                id: "qID1",
                question: "What do you think about our product?",
                description: "Please share your thoughts",
                descriptionContentType: .text,
                optional: false,
                buttonText: nil,
                originalQuestionIndex: 0,
                branching: nil,
                translations: nil
            )),
            .singleChoice(PostHogMultipleSurveyQuestion(
                id: "qID2",
                question: "How likely are you to recommend us?",
                description: "Please select one option",
                descriptionContentType: .text,
                optional: false,
                buttonText: nil,
                originalQuestionIndex: 1,
                branching: nil,
                translations: nil,
                choices: ["Very likely", "Somewhat likely", "Not likely"],
                hasOpenChoice: false,
                shuffleOptions: false
            )),
            .rating(PostHogRatingSurveyQuestion(
                id: "qID3",
                question: "Rate your experience",
                description: "1 = Poor, 5 = Excellent",
                descriptionContentType: .text,
                optional: false,
                buttonText: nil,
                originalQuestionIndex: 2,
                branching: nil,
                translations: nil,
                display: .number,
                scale: .fivePoint,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )),
        ])

        let responses: [String: PostHogSurveyResponse] = [
            integration.testGetResponseKey(questionId: "qID1"): .openEnded("Great product!"),
            integration.testGetResponseKey(questionId: "qID2"): .singleChoice("Very likely"),
            integration.testGetResponseKey(questionId: "qID3"): .rating(4),
        ]

        integration.testSendSurveySentEvent(survey: survey, responses: responses)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey sent")
        #expect(event.properties["$survey_name"] as? String == survey.name)
        #expect(event.properties["$survey_id"] as? String == survey.id)

        let setProperties = event.properties["$set"] as? [String: Any]
        #expect(setProperties?["$survey_responded/\(survey.id)"] as? Bool == true)

        let questions = event.properties["$survey_questions"] as? [[String: Any]]
        #expect(questions?.count == 3)

        #expect(event.properties["$survey_response_qID1"] as? String == "Great product!")
        #expect(event.properties["$survey_response_qID2"] as? String == "Very likely")
        #expect(event.properties["$survey_response_qID3"] as? String == "4")

        postHog.close()
        postHog.reset()
    }

    @Test("survey sent event with a single response")
    func surveySentEventWithSingleResponse() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "single-response-survey",
            name: "Single Response Survey",
            questions: [
                .open(PostHogOpenSurveyQuestion(
                    id: "qID1",
                    question: "What do you think about our product?",
                    description: "Please share your thoughts",
                    descriptionContentType: .text,
                    optional: false,
                    buttonText: nil,
                    originalQuestionIndex: 0,
                    branching: nil,
                    translations: nil
                )),
            ]
        )

        let responses: [String: PostHogSurveyResponse] = [
            integration.testGetResponseKey(questionId: "qID1"): .openEnded("Excellent product!"),
        ]

        integration.testSendSurveySentEvent(survey: survey, responses: responses)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey sent")
        #expect(event.properties["$survey_name"] as? String == "Single Response Survey")
        #expect(event.properties["$survey_id"] as? String == "single-response-survey")
        #expect(event.properties["$survey_response_qID1"] as? String == "Excellent product!")

        let setProperties = event.properties["$set"] as? [String: Any]
        #expect(setProperties?["$survey_responded/single-response-survey"] as? Bool == true)

        postHog.close()
        postHog.reset()
    }

    // MARK: - Survey Dismissed Event Tests

    @Test("survey dismissed event has correct name and properties")
    func surveyDismissedEventHasCorrectNameAndProperties() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "dismissed-survey",
            name: "Dismissed Survey",
            questions: defaultQuestions
        )

        integration.testSendSurveyDismissedEvent(survey: survey)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey dismissed")
        #expect(event.properties["$survey_name"] as? String == "Dismissed Survey")
        #expect(event.properties["$survey_id"] as? String == "dismissed-survey")

        let setProperties = event.properties["$set"] as? [String: Any]
        #expect(setProperties?["$survey_dismissed/dismissed-survey"] as? Bool == true)

        postHog.close()
        postHog.reset()
    }

    @Test("survey dismissed event includes responses and partial completion when there are answers")
    func surveyDismissedEventIncludesResponsesWhenThereAreAnswers() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "dismissed-responses-survey",
            name: "Dismissed Responses Survey",
            questions: defaultQuestions
        )

        let responses: [String: PostHogSurveyResponse] = [
            integration.testGetResponseKey(questionId: "qID1"): .openEnded("Great product!"),
            integration.testGetResponseKey(questionId: "qID2"): .singleChoice("Very likely"),
            integration.testGetResponseKey(questionId: "qID3"): .rating(4),
            "$survey_response": .openEnded("Great product!"),
            "$survey_response_1": .singleChoice("Very likely"),
            "$survey_response_2": .rating(4),
        ]

        integration.testSendSurveyDismissedEvent(survey: survey, responses: responses)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey dismissed")
        #expect(event.properties["$survey_partially_completed"] as? Bool == true)
        #expect(event.properties["$survey_response_qID1"] as? String == "Great product!")
        #expect(event.properties["$survey_response_qID2"] as? String == "Very likely")
        #expect(event.properties["$survey_response_qID3"] as? String == "4")
        #expect(event.properties["$survey_response"] as? String == "Great product!")
        #expect(event.properties["$survey_response_1"] as? String == "Very likely")
        #expect(event.properties["$survey_response_2"] as? String == "4")

        let questions = event.properties["$survey_questions"] as? [[String: Any]]
        #expect(questions?.count == 3)
        #expect(questions?[0]["response"] as? String == "Great product!")
        #expect(questions?[1]["response"] as? String == "Very likely")
        #expect(questions?[2]["response"] as? String == "4")

        postHog.close()
        postHog.reset()
    }

    @Test("survey dismissed event marks partial completion false when there are no answers")
    func surveyDismissedEventMarksPartialCompletionFalseWhenThereAreNoAnswers() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "dismissed-empty-survey",
            name: "Dismissed Empty Survey",
            questions: defaultQuestions
        )

        integration.testSendSurveyDismissedEvent(survey: survey, responses: [:])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        #expect(event.event == "survey dismissed")
        #expect(event.properties["$survey_partially_completed"] as? Bool == false)

        let questions = event.properties["$survey_questions"] as? [[String: Any]]
        #expect(questions?.count == 3)
        #expect(questions?[0]["response"] == nil)
        #expect(questions?[1]["response"] == nil)
        #expect(questions?[2]["response"] == nil)

        postHog.close()
        postHog.reset()
    }

    @Test("survey dismissed event with iteration has correct interaction property")
    func surveyDismissedEventWithIterationHasCorrectInteractionProperty() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "iter-dismissed-survey",
            name: "Iteration Dismissed Survey",
            questions: defaultQuestions,
            currentIteration: 2
        )

        integration.testSendSurveyDismissedEvent(survey: survey)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events[0]

        let setProperties = event.properties["$set"] as? [String: Any]
        #expect(setProperties?["$survey_dismissed/iter-dismissed-survey/2"] as? Bool == true)

        postHog.close()
        postHog.reset()
    }

    // MARK: - Base Survey Event Properties Tests

    @Test("base survey event properties include all required fields")
    func baseSurveyEventPropertiesIncludeAllRequiredFields() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "complete-survey-id",
            name: "Complete Survey",
            questions: defaultQuestions,
            currentIteration: 5,
            currentIterationStartDate: Date(timeIntervalSince1970: 1640995200) // 2022-01-01
        )

        let properties = integration.testGetBaseSurveyEventProperties(for: survey)

        #expect(properties["$survey_name"] as? String == "Complete Survey")
        #expect(properties["$survey_id"] as? String == "complete-survey-id")
        #expect(properties["$survey_iteration"] as? Int == 5)
        #expect(properties["$survey_iteration_start_date"] as? String == "2022-01-01T00:00:00.000Z")

        postHog.close()
        postHog.reset()
    }

    @Test("base survey event properties exclude nil values")
    func baseSurveyEventPropertiesExcludeNilValues() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let survey = getTestSurvey(
            id: "minimal-survey-id",
            name: "Minimal Survey",
            questions: defaultQuestions
        )

        let properties = integration.testGetBaseSurveyEventProperties(for: survey)

        #expect(properties["$survey_name"] as? String == "Minimal Survey")
        #expect(properties["$survey_id"] as? String == "minimal-survey-id")
        #expect(properties["$survey_iteration"] == nil)
        #expect(properties["$survey_iteration_start_date"] == nil)

        postHog.close()
        postHog.reset()
    }

    @Test("survey interaction property formats correctly")
    func surveyInteractionPropertyFormatsCorrectly() async throws {
        let postHog = getSut()

        let integration = try getSurveyIntegration(postHog)

        let surveyWithoutIteration = getTestSurvey(
            id: "test-survey",
            name: "Test Survey",
            questions: defaultQuestions
        )

        let propertyWithoutIteration = integration.testGetSurveyInteractionProperty(
            survey: surveyWithoutIteration,
            property: "responded"
        )
        #expect(propertyWithoutIteration == "$survey_responded/test-survey")

        let surveyWithIteration = getTestSurvey(
            id: "test-survey",
            name: "Test Survey",
            questions: defaultQuestions,
            currentIteration: 3
        )

        let propertyWithIteration = integration.testGetSurveyInteractionProperty(
            survey: surveyWithIteration,
            property: "dismissed"
        )
        #expect(propertyWithIteration == "$survey_dismissed/test-survey/3")

        postHog.close()
        postHog.reset()
    }
}
