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

    func getSut() -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.flushAt = 1
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    func getSurveyIntegration(_ postHog: PostHogSDK) throws -> PostHogSurveyIntegration {
        PostHogSurveyIntegration.clearInstalls()
        let integration = PostHogSurveyIntegration()
        let installResult = integration.install(postHog)
        try #require(installResult == .installed)
        return integration
    }

    private func partialResponseSurvey(enabled: Bool?, branching: [String: Any]? = nil) throws -> PostHogSurvey {
        var first: [String: Any] = ["id": "first", "type": "open", "question": "First?", "optional": true]
        first["branching"] = branching
        var json: [String: Any] = [
            "id": "partial-survey", "name": "Partial survey", "type": "popover",
            "questions": [first, ["id": "second", "type": "open", "question": "Second?"]],
        ]
        json["enable_partial_responses"] = enabled
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PostHogSurvey.self, from: JSONSerialization.data(withJSONObject: json))
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
