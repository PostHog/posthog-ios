//
//  PostHogSurveysTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 21/01/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Test Surveys")
enum PostHogSurveysTest {
    @Suite("Test decoding surveys from remote config")
    struct TestDecodingSurveys {
        @Test("survey decodes correctly")
        func surveyDecodesCorrectly() throws {
            let data = try loadFixture("fixture_survey_basic")
            let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

            #expect(sut.id == "01947134-8a35-0000-549a-193b86fa2e44")
            #expect(sut.name == "Core Web Vitals feature request")
            #expect(sut.type == .popover)
            #expect(sut.featureFlagKeys == [
                PostHogSurveyFeatureFlagKeyValue(key: "flag1", value: "linked-flag-key"),
                PostHogSurveyFeatureFlagKeyValue(key: "flag2", value: "survey-targeting-flag-key"),
            ])
            #expect(sut.targetingFlagKey == "survey-targeting-flag-key")
            #expect(sut.internalTargetingFlagKey == "survey-targeting-88af4df282-custom")
            #expect(sut.questions.count == 1)

            if case let .open(question) = sut.questions[0] {
                #expect(question.question == "What would you like to see in our Core Web Vitals product?")
                #expect(question.description == "Core Web Vitals just launched and we're interested in hearing (reading?) from you on what you think we're missing with this product")
                #expect(question.originalQuestionIndex == 0)
                #expect(question.descriptionContentType == .text)
            } else {
                throw TestError("Expected basic question type")
            }

            #expect(sut.conditions?.url == "core-web-vitals")
            #expect(sut.appearance?.position == .right)
            #expect(sut.appearance?.fontFamily == "system-ui")
            #expect(sut.appearance?.whiteLabel == false)
            #expect(sut.appearance?.borderColor == "#c9c6c6")
            #expect(sut.appearance?.placeholder == "Start typing...")
            #expect(sut.appearance?.backgroundColor == "#eeeded")
            #expect(sut.appearance?.ratingButtonColor == "white")
            #expect(sut.appearance?.submitButtonColor == "black")
            #expect(sut.appearance?.submitButtonTextColor == "white")
            #expect(sut.appearance?.thankYouMessageHeader == "Thank you for your feedback!")
            #expect(sut.appearance?.displayThankYouMessage == true)
            #expect(sut.appearance?.ratingButtonActiveColor == "black")
            #expect(sut.appearance?.surveyPopupDelaySeconds == 5)
            #expect(sut.startDate.map(ISO8601DateFormatter().string) == "2025-01-16T22:23:38Z")
            #expect(sut.endDate == nil)
            #expect(sut.currentIteration == 1)
            #expect(sut.currentIterationStartDate.map(ISO8601DateFormatter().string) == "2024-12-12T18:58:22Z")
        }

        @Suite("Survey question types decode correctly")
        struct SurveyQuestionTypeDecodeTests {
            @Test("basic question decodes correctly")
            func basicQuestionDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_question_basic")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .open(question) = sut.questions[0] {
                    #expect(question.question == "What would you like to see in our Core Web Vitals product?")
                    #expect(question.description == "Core Web Vitals just launched and we're interested in hearing (reading?) from you on what you think we're missing with this product")
                    #expect(question.descriptionContentType == .text)
                    #expect(question.originalQuestionIndex == 0)
                } else {
                    throw TestError("Expected a basic question")
                }
            }

            @Test("single-choice question decodes correctly")
            func singleChoiceQuestionDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_question_single_choice")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .singleChoice(question) = sut.questions[0] {
                    #expect(question.choices == ["Heck yeah", "Nope, I'm good"])
                    #expect(question.question == "Would you be interested in being part of a PostHog community event in your city?")
                    #expect(question.buttonText == "Submit")
                    #expect(question.originalQuestionIndex == 0)
                    #expect(question.descriptionContentType == .text)
                } else {
                    throw TestError("Expected a single choice question")
                }
            }

            @Test("multiple-choice question decodes correctly")
            func multipleChoiceQuestionDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_question_multiple_choice")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .multipleChoice(question) = sut.questions[0] {
                    #expect(question.choices == [
                        "Meet new people",
                        "Build stuff (hackathon style)",
                        "Product growth hack (evolve your existing product, not start from scratch)",
                        "Learn things (talks, discussions)",
                        "Eat, drink and vibe (chill)",
                        "Something else",
                    ])
                    #expect(question.question == "Let's say there's a meetup. What would you hope to get out of it? ")
                    #expect(question.buttonText == "Submit")
                    #expect(question.hasOpenChoice == true)
                    #expect(question.originalQuestionIndex == 2)
                    #expect(question.descriptionContentType == .text)
                } else {
                    throw TestError("Expected a multiple choice question")
                }
            }

            @Test("link question decodes correctly")
            func linkQuestionDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_question_link")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .link(question) = sut.questions[0] {
                    #expect(question.link == "https://cal.com/david-posthog/user-interview")
                    #expect(question.question == "Share your thoughts")
                    #expect(question.buttonText == "Schedule")
                    #expect(question.description == "We'd love to get your first impressions of the feature on a video call")
                } else {
                    throw TestError("Expected a link question")
                }
            }

            @Test("rating question decodes correctly")
            func ratingQuestionDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_question_rating")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .rating(question) = sut.questions[0] {
                    #expect(question.scale == .tenPoint)
                    #expect(question.display == .number)
                    #expect(question.question == "How likely are you to recommend us to a friend?")
                    #expect(question.lowerBoundLabel == "Unlikely")
                    #expect(question.upperBoundLabel == "Very likely")
                    #expect(question.originalQuestionIndex == 0)
                    #expect(question.descriptionContentType == .text)
                } else {
                    throw TestError("Expected a rating question")
                }
            }
        }

        @Suite("Question branching decodes correctly")
        struct QuestionBranchingDecodesCorrectly {
            @Test("next branching decodes correctly")
            func nextBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_next")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case .next = sut.questions[0].branching {
                    // nothing
                } else {
                    throw TestError("Expected next branching")
                }
            }

            @Test("end branching decodes correctly")
            func endBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_end")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case .end = sut.questions[0].branching {
                    // nothing
                } else {
                    throw TestError("Expected end branching")
                }
            }

            @Test("specific question branching decodes correctly")
            func specificQuestionBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_specific")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .specificQuestion(index: index) = sut.questions[0].branching {
                    #expect(index == 2)
                } else {
                    throw TestError("Expected specific question branching")
                }
            }

            @Test("response-based branching decodes correctly")
            func responseBasedBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_response_based")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .responseBased(values) = sut.questions[0].branching {
                    #expect(values["0"] as? Int == 1)
                    #expect(values["1"] as? String == "end")
                } else {
                    throw TestError("Expected response based branching")
                }
            }

            @Test("response-based with linkert branching decodes correctly")
            func responseBasedWithLinkertBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_response_based_linkert")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .responseBased(values) = sut.questions[0].branching {
                    #expect(values["negative"] as? Int == 1)
                    #expect(values["neutral"] as? Int == 2)
                    #expect(values["positive"] as? Int == 3)
                } else {
                    throw TestError("Expected response based branching")
                }
            }

            @Test("response-based with empty values branching decodes correctly")
            func responseBasedWithEmptyValuesBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_response_based_empty")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if case let .responseBased(values) = sut.questions[0].branching {
                    #expect(values.isEmpty)
                } else {
                    throw TestError("Expected response based branching")
                }
            }
        }

        @Suite("Question display conditions decodes correctly")
        struct DisplayConditionsDecodesCorrectly {
            @Test("event condition decodes correctly")
            func eventConditionDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_conditions_event")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let events = sut.conditions?.events {
                    #expect(events.values == [PostHogEventCondition(name: "dashboard loading time")])
                } else {
                    throw TestError("Expected event display condition")
                }
            }

            @Test("repeated event condition decodes correctly")
            func repeatedEventConditionDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_conditions_event_repeated")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let events = sut.conditions?.events {
                    #expect(events.values == [PostHogEventCondition(name: "dashboard loading time")])
                    #expect(events.repeatedActivation == true)
                } else {
                    throw TestError("Expected repeated event display condition")
                }
            }

            @Test("device type condition decodes correctly")
            func deviceTypeConditionDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_conditions_device_type")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let types = sut.conditions?.deviceTypes {
                    #expect(types == ["Mobile"])
                } else {
                    throw TestError("Expected event display condition")
                }
            }

            @Test("url condition decodes correctly")
            func urlConditionDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_conditions_url")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url {
                    #expect(url == "ScreenName")
                } else {
                    throw TestError("Expected url display condition")
                }
            }
        }

        @Suite("Url match types decode correctly")
        struct UrlMatchTypeDecodesCorrectly {
            @Test("exact url match type decodes correctly")
            func exactUrlMatchTypeDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_url_match_type_exact")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url, let matchType = sut.conditions?.urlMatchType {
                    #expect(url == "ScreenName")
                    #expect(matchType == .exact)
                } else {
                    throw TestError("Expected url match type")
                }
            }

            @Test("is_not url match type decodes correctly")
            func isNotRegexUrlMatchTypeDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_url_match_type_is_not")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url, let matchType = sut.conditions?.urlMatchType {
                    #expect(url == "ScreenName")
                    #expect(matchType == .isNot)
                } else {
                    throw TestError("Expected url match type")
                }
            }

            @Test("icontains url match type decodes correctly")
            func iContainsUrlMatchTypeDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_url_match_type_icontains")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url, let matchType = sut.conditions?.urlMatchType {
                    #expect(url == "ScreenName")
                    #expect(matchType == .iContains)
                } else {
                    throw TestError("Expected url match type")
                }
            }

            @Test("not_icontains url match type decodes correctly")
            func notIContainsUrlMatchTypeDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_url_match_type_not_icontains")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url, let matchType = sut.conditions?.urlMatchType {
                    #expect(url == "ScreenName")
                    #expect(matchType == .notIContains)
                } else {
                    throw TestError("Expected url match type")
                }
            }

            @Test("regex url match type decodes correctly")
            func regexUrlMatchTypeDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_url_match_type_regex")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url, let matchType = sut.conditions?.urlMatchType {
                    #expect(url == "ScreenName")
                    #expect(matchType == .regex)
                } else {
                    throw TestError("Expected url match type")
                }
            }

            @Test("not_regex url match type decodes correctly")
            func notRegexUrlMatchTypeDecodesCorrectly() async throws {
                let data = try loadFixture("fixture_survey_url_match_type_not_regex")
                let sut = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)

                if let url = sut.conditions?.url, let matchType = sut.conditions?.urlMatchType {
                    #expect(url == "ScreenName")
                    #expect(matchType == .notRegex)
                } else {
                    throw TestError("Expected url match type")
                }
            }
        }
    }

    @Suite("Test SurveyUrlMatchType match function")
    struct TestSurveyUrlMatching {
        static let regexMap: [(url: String, regex: String, shouldMatch: Bool)] = [
            // url
            (url: "https://example.com/survey/123", regex: "https://example.com/survey/(\\d+)", shouldMatch: true),
            // screen name
            (url: "MyScreenName", regex: "^My", shouldMatch: true),
            // case sensitivity
            (url: "myScreenName", regex: "^My", shouldMatch: false),
            // special characters
            (url: "User.Profile-Page/123", regex: "\\.[A-Za-z]+-[A-Za-z]+/\\d+", shouldMatch: true),
            // empty strings
            (url: "", regex: ".*", shouldMatch: true),
            // word boundaries
            (url: "UserProfile", regex: "\\bProfile\\b", shouldMatch: false),
            (url: "User Profile", regex: "\\bProfile\\b", shouldMatch: true),
        ]

        @Test("matches regex correctly", arguments: regexMap)
        func matchesRegex(url: String, regex: String, shouldMatch: Bool) {
            let sut: PostHogSurveyMatchType = .regex
            let matches = sut.matchFunction

            #expect(matches([url], regex) == shouldMatch)
        }

        @Test("matches not_regex correctly", arguments: regexMap)
        func matchesNotRegex(url: String, regex: String, shouldMatch: Bool) {
            let sut: PostHogSurveyMatchType = .notRegex
            let matches = sut.matchFunction

            #expect(matches([url], regex) != shouldMatch)
        }

        @Test("matches icontains correctly")
        func matchesIcontains() {
            let sut: PostHogSurveyMatchType = .iContains
            let matches = sut.matchFunction

            #expect(matches(["Hello"], "hello") == true)
            #expect(matches(["Hello"], "HeLLo") == true)
            #expect(matches(["Hello"], "heLLo") == true)
            #expect(matches(["Hello", "PostHogTest"], "PostHog") == true)
            #expect(matches(["Hello"], "PostHog") == false)
        }

        @Test("matches not_icontains correctly")
        func matchesNotIcontains() {
            let sut: PostHogSurveyMatchType = .notIContains
            let matches = sut.matchFunction

            #expect(matches(["Hello"], "hello") == false)
            #expect(matches(["Hello"], "HeLLo") == false)
            #expect(matches(["Hello"], "heLLo") == false)
            #expect(matches(["Hello", "PostHogTest"], "PostHog") == false)
            #expect(matches(["Hello"], "PostHog") == true)
        }

        @Test("matches exact correctly")
        func matchesExact() {
            let sut: PostHogSurveyMatchType = .exact
            let matches = sut.matchFunction

            #expect(matches(["Hello"], "hello") == false)
            #expect(matches(["HeLLo"], "hello") == false)
            #expect(matches(["HeLlo"], "hello") == false)
            #expect(matches(["Hello"], "Hello") == true)
            #expect(matches(["Hello", "PostHog"], "Hello") == true)
        }

        @Test("matches is_not correctly")
        func matchesIsNot() {
            let sut: PostHogSurveyMatchType = .isNot
            let matches = sut.matchFunction

            #expect(matches(["Hello"], "hello") == true)
            #expect(matches(["Hello"], "HeLLo") == true)
            #expect(matches(["Hello"], "heLLo") == true)
            #expect(matches(["Hello"], "Hello") == false)
            #expect(matches(["Hello", "PostHog"], "Hello") == false)
        }
    }

    @Suite("Test canActivateRepeatedly")
    struct TestCanActivateRepeatedly {
        private func getSut(repeatedActivation: Bool?, values: [PostHogEventCondition]) -> PostHogSurvey {
            PostHogSurvey(
                id: "id",
                name: "name",
                type: .popover,
                questions: [],
                featureFlagKeys: nil,
                linkedFlagKey: nil,
                targetingFlagKey: nil,
                internalTargetingFlagKey: nil,
                conditions: PostHogSurveyConditions(
                    url: nil,
                    urlMatchType: nil,
                    selector: nil,
                    deviceTypes: nil,
                    deviceTypesMatchType: nil,
                    seenSurveyWaitPeriodInDays: nil,
                    events: PostHogSurveyEventConditions(
                        repeatedActivation: repeatedActivation,
                        values: values
                    ),
                    actions: nil
                ),
                appearance: nil,
                currentIteration: nil,
                currentIterationStartDate: nil,
                startDate: nil,
                endDate: nil
            )
        }

        @Test("returns false when survey has no events")
        func returnsFalseWhenSurveyHasNoEvents() {
            let sut = getSut(
                repeatedActivation: true,
                values: []
            )

            #expect(sut.canActivateRepeatedly == false)
        }

        @Test("returns true when survey has events and repeatedActivation is true")
        func returnsTrueWhenSurveyHasEventsAndRepeatedActivationIsAlsoTrue() {
            let sut = getSut(
                repeatedActivation: true,
                values: [
                    PostHogEventCondition(name: "first event"),
                    PostHogEventCondition(name: "second event"),
                ]
            )

            #expect(sut.canActivateRepeatedly == true)
        }

        @Test("returns false when survey has events but repeatedActivation is false")
        func returnsFalseWhenSurveyHasEventsButRepeatedActivationIsFalse() {
            let sut = getSut(
                repeatedActivation: false,
                values: [
                    PostHogEventCondition(name: "first event"),
                    PostHogEventCondition(name: "second event"),
                ]
            )

            #expect(sut.canActivateRepeatedly == false)
        }
    }

    @Suite("Test getActiveMatchingSurveys", .serialized)
    class TestGetActiveSurveys {
        let server: MockPostHogServer
        let postHog: PostHogSDK

        init() {
            let config = PostHogConfig(apiKey: "test", host: "http://localhost:9090")
            config._surveys = true
            postHog = PostHogSDK.with(config)
            let storage = PostHogStorage(config)
            storage.reset()
            server = MockPostHogServer()
            server.featureFlags = [
                "linked-flag-enabled": true,
                "linked-flag-disabled": false,
                "survey-targeting-flag-enabled": true,
                "survey-targeting-flag-disabled": false,
                "internal-targeting-flag-enabled": true,
                "internal-targeting-flag-disabled": false,
            ]
            server.start()
        }

        deinit {
            server.stop()
            postHog.close()
            postHog.reset()
        }

        let draftSurvey =
            """
            {
                "id": "draft_id",
                "name": "Draft Survey",
                "type": "popover",
                "questions": [
                    {
                        "type": "open",
                        "question": "What is a completed survey?"
                    }
                ]
            }
            """

        let activeSurvey =
            """
            {
                "id": "active_id",
                "name": "Active Survey",
                "type": "popover",
                "questions": [
                    {
                        "type": "open",
                        "question": "What is a completed survey?"
                    }
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let completedSurvey =
            """
            {
                "id": "completed_id",
                "name": "Completed Survey",
                "type": "popover",
                "questions": [
                    {
                        "type": "open",
                        "question": "What is a completed survey?"
                    }
                ],
                "start_date": "2024-07-23T09:18:18.376000Z",
                "end_date": "2025-03-03T09:18:18.376000Z"
            }
            """

        let surveyWithDesktopDevice =
            """
            {
                "id": "desktop_id",
                "name": "Active Survey",
                "type": "popover",
                "questions": [
                    {
                        "type": "open",
                        "question": "What is a completed survey?"
                    }
                ],
                "conditions": { 
                    "deviceTypes": ["Desktop"], 
                    "deviceTypesMatchType": "icontains" 
                },
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let surveyWithMobileDevice =
            """
            {
                "id": "mobile_id",
                "name": "Active Survey",
                "type": "popover",
                "questions": [
                    {
                        "type": "open",
                        "question": "What is a completed survey?"
                    }
                ],
                "conditions": { 
                    "deviceTypes": ["Mobile"], 
                    "deviceTypesMatchType": "icontains" 
                },
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let surveysWithFeatureFlags =
            """
            {
                "name": "survey with feature flags",
                "id": "survey-with-flags",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "feature_flag_keys": [
                    { "key": "flag1", "value": "linked-flag-enabled" },
                    { "key": "flag2", "value": "survey-targeting-flag-enabled" },
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            },
            {
                "name": "survey with disabled feature flags",
                "id": "survey-with-disabled-flags",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "feature_flag_keys": [
                    { "key": "flag1", "value": "linked-flag-disabled" },
                    { "key": "flag2", "value": "survey-targeting-flag-disabled" },
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            },
            {
                "name": "survey without feature flags",
                "id": "survey-without-flags",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let surveysWithMissingKeysAndValues =
            """
            {
                "name": "survey with missing keys",
                "id": "survey-with-missing-keys",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "feature_flag_keys": [
                    { "key": "", "value": "linked-flag-enabled" },
                    { "key": "", "value": "" },
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            },
            {
                "name": "survey with missing values",
                "id": "survey-with-missing-values",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "feature_flag_keys": [
                    { "key": "flag1", "value": "" },
                    { "key": "flag2", "value": "" },
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let surveyWithEnabledAndDisabledFlags =
            """
            {
                "name": "survey with disabled and enabled feature flags",
                "id": "survey-with-mixed-flags",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "feature_flag_keys": [
                    { "key": "flag1", "value": "linked-flag-disabled" },
                    { "key": "flag2", "value": "linked-flag-enabled" },
                ],
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let surveyWithEnabledInternalTargetingFlag =
            """
            {
                "name": "survey with internal flag enabled",
                "id": "survey-with-internal-flag-enabled",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "internal_targeting_flag_key": "internal-targeting-flag-enabled",
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        let surveyWithDisabledInternalTargetingFlag =
            """
            {
                "name": "survey with internal flag disabled",
                "id": "survey-with-internal-flag-disabled",
                "description": "survey with feature flags description",
                "type": "popover",
                "questions": [
                    { 
                        "type": "open", 
                        "question": "what do you think?" 
                    }
                ],
                "internal_targeting_flag_key": "internal-targeting-flag-disabled",
                "start_date": "2024-07-23T09:18:18.376000Z"
            }
            """

        private func getSut(surveys: [String]) -> PostHogSurveyIntegration {
            server.remoteConfigSurveys = "[\(surveys.joined(separator: ","))]"
            let sut = PostHogSurveyIntegration()
            PostHogSurveyIntegration.clearInstalls()
            try! sut.install(postHog)
            return sut
        }

        @Test("returns surveys that are active")
        func returnsActiveSurveys() async {
            let surveys: [String] = [
                draftSurvey,
                activeSurvey,
                completedSurvey,
            ]

            let sut = getSut(surveys: surveys)

            let matchedSurveys: [PostHogSurvey] = await withCheckedContinuation { continuation in
                sut.getActiveMatchingSurveys(forceReload: true) {
                    continuation.resume(with: .success($0))
                }
            }

            #expect(matchedSurveys.map(\.id) == ["active_id"])
        }

        @Test("returns surveys that match device type")
        func returnsSurveysThatMatchDeviceType() async {
            let surveys: [String] = [
                draftSurvey,
                activeSurvey,
                completedSurvey,
                surveyWithDesktopDevice,
                surveyWithMobileDevice,
            ]

            let sut = getSut(surveys: surveys)

            let matchedSurveys: [PostHogSurvey] = await withCheckedContinuation { continuation in
                sut.getActiveMatchingSurveys(forceReload: true) {
                    continuation.resume(with: .success($0))
                }
            }

            if let currentDeviceType = PostHogContext.deviceType?.lowercased() {
                #expect(matchedSurveys.map(\.id) == ["active_id", "\(currentDeviceType)_id"])
            } else {
                #expect(matchedSurveys.map(\.id) == ["active_id"])
            }
        }

        @Test("returns only surveys with enabled feature flags")
        func returnsOnlySurveysWithEnabledFeatureFlags() async {
            let sut = getSut(surveys: [surveysWithFeatureFlags])

            let matchedSurveys: [PostHogSurvey] = await withCheckedContinuation { continuation in
                sut.getActiveMatchingSurveys(forceReload: true) {
                    continuation.resume(with: .success($0))
                }
            }

            #expect(matchedSurveys.map(\.id).contains("survey-with-flags"))
            #expect(matchedSurveys.map(\.id).contains("survey-without-flags"))
            #expect(!matchedSurveys.map(\.id).contains("survey-with-disabled-flags"))
        }

        @Test("Should not return surveys when any feature flag is disabled")
        func shouldFilterOutSurveysWhenAnyFlagIsDisabled() async {
            let sut = getSut(surveys: [surveyWithEnabledAndDisabledFlags])

            let matchedSurveys: [PostHogSurvey] = await withCheckedContinuation { continuation in
                sut.getActiveMatchingSurveys(forceReload: true) {
                    continuation.resume(with: .success($0))
                }
            }

            #expect(matchedSurveys.isEmpty)
        }

        @Test("skips checking flags for surveys with missing keys or values ")
        func shouldIgnoreSurveysWithMissingFeatureFlagsKeysOrValues() async {
            let sut = getSut(surveys: [surveysWithMissingKeysAndValues])

            let matchedSurveys: [PostHogSurvey] = await withCheckedContinuation { continuation in
                sut.getActiveMatchingSurveys(forceReload: true) {
                    continuation.resume(with: .success($0))
                }
            }

            #expect(matchedSurveys.map(\.id).contains("survey-with-missing-keys"))
            #expect(matchedSurveys.map(\.id).contains("survey-with-missing-values"))
        }

        @Test("returns surveys that match internal targeting flags")
        func returnsSurveysThatMatchInternalTargetingFlags() async {
            let sut = getSut(surveys: [surveyWithEnabledInternalTargetingFlag])

            let matchedSurveys: [PostHogSurvey] = await withCheckedContinuation { continuation in
                sut.getActiveMatchingSurveys(forceReload: true) {
                    continuation.resume(with: .success($0))
                }
            }

            #expect(matchedSurveys.map(\.id) == ["survey-with-internal-flag-enabled"])
        }
    }

    @Suite("Test conditional branching", .serialized)
    class TestConfitionalBranchingLogic {
        @Test("returns next question index when no branching")
        func returnsNextQuestionIndexWhenNoBranching() throws {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .open(.testInstance(question: "q1")),
                    .open(.testInstance(question: "q2")),
                    .open(.testInstance(question: "q3")),
                ]
            )

            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .openEnded("response 1")) {
                #expect(nextIndex == 1)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 1, response: .openEnded("response 2")) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 2, response: .openEnded("response 3")) {
                #expect(nextIndex == 2)
                #expect(isCompleted == true)
            } else {
                throw TestError("Expected next question state")
            }
        }

        @Test("completes survey with single question")
        func completesSurveyWithSingleQuestion() throws {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .open(.testInstance(question: "q1")),
                ]
            )

            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .openEnded("response")) {
                #expect(nextIndex == 0)
                #expect(isCompleted == true)
            } else {
                throw TestError("Expected next question state")
            }
        }

        @Test("ends survey when branching is end")
        func endsSurveyWhenBranchingIsEnd() throws {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .open(.testInstance(question: "q1", branching: .end)),
                    .open(.testInstance(question: "q2")),
                ]
            )

            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .openEnded("response")) {
                #expect(nextIndex == 0)
                #expect(isCompleted == true)
            } else {
                throw TestError("Expected next question state")
            }
        }

        @Test("jumps to specific question when branching to specific question")
        func jumpsToSpecificQuestionWhenBranchingToSpecificQuestion() throws {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .rating(.testInstance(
                        question: "q1",
                        display: .number,
                        scale: .tenPoint,
                        branching: .specificQuestion(index: 2)
                    )),
                    .open(.testInstance(question: "q2")),
                    .open(.testInstance(question: "q3")),
                    .open(.testInstance(question: "q4")),
                ]
            )

            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .openEnded("response 1")) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 2, response: .openEnded("response 2")) {
                #expect(nextIndex == 3)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 3, response: .openEnded("response 3")) {
                #expect(nextIndex == 3)
                #expect(isCompleted == true)
            } else {
                throw TestError("Expected next question state")
            }
        }

        @Test("jumps to last question when branching is out of bounds")
        func jumpsToLastQuestionWhenBranchingOutOfBounds() throws {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .open(.testInstance(question: "q1", branching: .specificQuestion(index: 5))),
                    .open(.testInstance(question: "q2")),
                    .open(.testInstance(question: "q3")),
                ]
            )

            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .openEnded("response 1")) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 2, response: .openEnded("response 2")) {
                #expect(nextIndex == 2)
                #expect(isCompleted == true)
            } else {
                throw TestError("Expected next question state")
            }
        }

        @Test("handles single choice response based branching")
        func handlesSingleChoiceResponseBasedBranching() throws {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .singleChoice(.testInstance(
                        question: "How satisfied are you with our product?",
                        choices: ["Very Dissatisfied", "Dissatisfied", "Neutral", "Satisfied", "Very Satisfied"],
                        branching: .responseBased(responseValues: [
                            "0": 1, // Very Dissatisfied -> Detractor path
                            "1": 1, // Dissatisfied -> Detractor path
                            "2": 2, // Neutral -> Neutral path
                            "3": 3, // Satisfied -> Promoter path
                            "4": 3, // Very Satisfied -> Promoter path
                        ])
                    )),
                    .open(.testInstance(question: "detractor", branching: .specificQuestion(index: 4))), // Detractor path
                    .open(.testInstance(question: "neutral", branching: .specificQuestion(index: 4))), // Neutral path
                    .open(.testInstance(question: "promoter", branching: .specificQuestion(index: 4))), // Promoter path
                    .open(.testInstance(question: "Final")), // Final question
                ]
            )

            // Test Very Satisfied/Satisfied path (promoter)
            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .singleChoice("Very Satisfied")) {
                #expect(nextIndex == 3)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 3, response: .openEnded("Great product!")) {
                #expect(nextIndex == 4)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            // Test Neutral path
            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .singleChoice("Neutral")) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 2, response: .openEnded("It's okay")) {
                #expect(nextIndex == 4)
                #expect(isCompleted == false)
            } else {
                throw TestError("Expected next question state")
            }

            // Test Dissatisfied/Very Dissatisfied path (detractor)
            sut.setShownSurvey(survey)

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .singleChoice("Very Dissatisfied")) {
                #expect(nextIndex == 1)
                #expect(isCompleted == false)
            }

            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 1, response: .openEnded("Needs work")) {
                #expect(nextIndex == 4)
                #expect(isCompleted == false)
            }

            // Complete final question for any path
            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 4, response: .singleChoice("Yes")) {
                #expect(nextIndex == 4)
                #expect(isCompleted == true)
            }
        }

        @Test("handles rating response based branching for scale 3")
        func handlesRatingResponseBasedBranchingForScale3() {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .rating(.testInstance(
                        question: "rating question",
                        display: .emoji,
                        scale: .threePoint,
                        branching: .responseBased(responseValues: ["negative": 1, "neutral": 2, "positive": 3])
                    )),
                    .open(.testInstance(question: "q2")),
                    .open(.testInstance(question: "q3")),
                    .open(.testInstance(question: "q4")),
                ]
            )

            sut.setShownSurvey(survey)

            // Test negative (1)
            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(1)) {
                #expect(nextIndex == 1)
                #expect(isCompleted == false)
            }

            // Test neutral (2)
            sut.setShownSurvey(survey)
            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(2)) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            }

            // Test positive (3)
            sut.setShownSurvey(survey)
            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(3)) {
                #expect(nextIndex == 3)
                #expect(isCompleted == false)
            }
        }

        @Test("handles rating response based branching for scale 5")
        func handlesRatingResponseBasedBranchingForScale5() {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .rating(.testInstance(
                        question: "rating question",
                        display: .emoji,
                        scale: .fivePoint,
                        branching: .responseBased(responseValues: ["negative": 1, "neutral": 2, "positive": 3])
                    )),
                    .open(.testInstance(question: "q2")),
                    .open(.testInstance(question: "q3")),
                    .open(.testInstance(question: "q4")),
                ]
            )

            // negative (1-2)
            for rating in 1 ... 2 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 1)
                    #expect(isCompleted == false)
                }
            }

            // neutral (3)
            sut.setShownSurvey(survey)
            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(3)) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            }

            // positive (4-5)
            for rating in 4 ... 5 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 3)
                    #expect(isCompleted == false)
                }
            }
        }

        @Test("handles rating response based branching for scale 7")
        func handlesRatingResponseBasedBranchingForScale7() {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .rating(.testInstance(
                        question: "rating question",
                        display: .number,
                        scale: .sevenPoint,
                        branching: .responseBased(responseValues: ["negative": 1, "neutral": 2, "positive": 3])
                    )),
                    .open(.testInstance(question: "q2")),
                    .open(.testInstance(question: "q3")),
                    .open(.testInstance(question: "q4")),
                ]
            )

            sut.setShownSurvey(survey)

            // negative (1-3)
            for rating in 1 ... 3 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 1)
                    #expect(isCompleted == false)
                }
            }

            // neutral (4)
            sut.setShownSurvey(survey)
            if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(4)) {
                #expect(nextIndex == 2)
                #expect(isCompleted == false)
            }

            // positive (5-7)
            for rating in 5 ... 7 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 3)
                    #expect(isCompleted == false)
                }
            }
        }

        @Test("handles NPS rating response based branching for scale 10")
        func handlesNPSRatingResponseBasedBranchingForScale10() {
            let sut = PostHogSurveyIntegration()

            let survey = PostHogSurvey.testInstance(
                name: "test survey",
                questions: [
                    .rating(.testInstance(
                        question: "q1",
                        display: .number,
                        scale: .tenPoint,
                        branching: .responseBased(responseValues: ["detractors": 1, "passives": 2, "promoters": 3])
                    )),
                    .open(.testInstance(question: "question_detractors", branching: .end)), // Detractors path
                    .open(.testInstance(question: "question_passives", branching: .end)), // Passives path
                    .open(.testInstance(question: "question_promoters", branching: .end)), // Promoters path
                ]
            )

            sut.setShownSurvey(survey)

            // detractors (0-6)
            for rating in 0 ... 6 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 1)
                    #expect(isCompleted == false)
                }
            }

            // passives (7-8)
            for rating in 7 ... 8 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 2)
                    #expect(isCompleted == false)
                }
            }

            // promoters (9-10)
            for rating in 9 ... 10 {
                sut.setShownSurvey(survey)
                if let (nextIndex, isCompleted) = sut.getNextQuestion(index: 0, response: .rating(rating)) {
                    #expect(nextIndex == 3)
                    #expect(isCompleted == false)
                }
            }
        }
    }
}

func loadFixture(_ name: String) throws -> Data {
    let url = Bundle.test.url(forResource: name, withExtension: "json")
    return try Data(contentsOf: url!)
}

private extension PostHogSurvey {
    static func testInstance(
        id: String = UUID().uuidString,
        name: String,
        type: PostHogSurveyType = .popover,
        questions: [PostHogSurveyQuestion] = [
            .open(
                PostHogOpenSurveyQuestion(
                    question: "Some question",
                    description: "Some description",
                    descriptionContentType: nil,
                    optional: nil,
                    buttonText: nil,
                    originalQuestionIndex: nil,
                    branching: nil
                )
            ),
        ],
        featureFlagKeys: [PostHogSurveyFeatureFlagKeyValue]? = nil,
        linkedFlagKey: String? = nil,
        targetingFlagKey: String? = nil,
        internalTargetingFlagKey: String? = nil,
        conditions: PostHogSurveyConditions? = nil,
        appearance: PostHogSurveyAppearance? = nil,
        currentIteration: Int? = nil,
        currentIterationStartDate: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> PostHogSurvey {
        PostHogSurvey(
            id: id,
            name: name,
            type: type,
            questions: questions,
            featureFlagKeys: featureFlagKeys,
            linkedFlagKey: linkedFlagKey,
            targetingFlagKey: targetingFlagKey,
            internalTargetingFlagKey: internalTargetingFlagKey,
            conditions: conditions,
            appearance: appearance,
            currentIteration: currentIteration,
            currentIterationStartDate: currentIterationStartDate,
            startDate: startDate,
            endDate: endDate
        )
    }
}

private extension PostHogOpenSurveyQuestion {
    static func testInstance(
        question: String,
        branching: PostHogSurveyQuestionBranching? = nil
    ) -> PostHogOpenSurveyQuestion {
        PostHogOpenSurveyQuestion(
            question: question,
            description: "",
            descriptionContentType: nil,
            optional: nil,
            buttonText: nil,
            originalQuestionIndex: nil,
            branching: branching
        )
    }
}

private extension PostHogMultipleSurveyQuestion {
    static func testInstance(
        question: String,
        choices: [String],
        branching: PostHogSurveyQuestionBranching? = nil
    ) -> PostHogMultipleSurveyQuestion {
        PostHogMultipleSurveyQuestion(
            question: question,
            description: "",
            descriptionContentType: nil,
            optional: nil,
            buttonText: nil,
            originalQuestionIndex: nil,
            branching: branching,
            choices: choices,
            hasOpenChoice: false,
            shuffleOptions: nil
        )
    }
}

private extension PostHogRatingSurveyQuestion {
    static func testInstance(
        question: String,
        display: PostHogSurveyRatingDisplayType,
        scale: PostHogSurveyRatingScale,
        branching: PostHogSurveyQuestionBranching? = nil
    ) -> PostHogRatingSurveyQuestion {
        PostHogRatingSurveyQuestion(
            question: question,
            description: "",
            descriptionContentType: nil,
            optional: nil,
            buttonText: nil,
            originalQuestionIndex: nil,
            branching: branching,
            display: display,
            scale: scale,
            lowerBoundLabel: "",
            upperBoundLabel: ""
        )
    }
}
