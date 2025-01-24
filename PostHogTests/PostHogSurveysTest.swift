//
//  PostHogSurveysTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 21/01/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite
enum PostHogSurveysDecodingTest {
    @Suite("Test decoding surveys from remote config")
    struct TestDecodingSurveys {
        @Test("survey decodes correctly")
        func surveyDecodesCorrectly() throws {
            let data = try loadFixture("fixture_survey_basic")
            let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

            #expect(sut.id == "01947134-8a35-0000-549a-193b86fa2e44")
            #expect(sut.name == "Core Web Vitals feature request")
            #expect(sut.type == .popover)
            #expect(sut.featureFlagKeys == [
                SurveyFeatureFlagKeyValue(key: "flag1", value: "linked-flag-key"),
                SurveyFeatureFlagKeyValue(key: "flag2", value: "survey-targeting-flag-key"),
            ])
            #expect(sut.targetingFlagKey == "survey-targeting-flag-key")
            #expect(sut.internalTargetingFlagKey == "survey-targeting-88af4df282-custom")
            #expect(sut.questions.count == 1)

            if case let .basic(question) = sut.questions[0] {
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
            #expect(sut.currentIteration == nil)
            #expect(sut.currentIterationStartDate == nil)
        }

        @Suite("Survey question types decode correctly")
        struct SurveyQuestionTypeDecodeTests {
            @Test("basic question decodes correctly")
            func basicQuestionDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_question_basic")
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

                if case let .basic(question) = sut.questions[0] {
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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

                if case let .rating(question) = sut.questions[0] {
                    #expect(question.scale == 10)
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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

                if case .next = sut.questions[0].branching {
                    // nothing
                } else {
                    throw TestError("Expected next branching")
                }
            }

            @Test("end branching decodes correctly")
            func endBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_end")
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

                if case .end = sut.questions[0].branching {
                    // nothing
                } else {
                    throw TestError("Expected end branching")
                }
            }

            @Test("specific question branching decodes correctly")
            func specificQuestionBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_specific")
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

                if case let .specificQuestion(index: index) = sut.questions[0].branching {
                    #expect(index == 2)
                } else {
                    throw TestError("Expected specific question branching")
                }
            }

            @Test("response-based branching decodes correctly")
            func responseBasedBranchingDecodesCorrectly() throws {
                let data = try loadFixture("fixture_survey_branching_response_based")
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

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
                let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

                if case let .responseBased(values) = sut.questions[0].branching {
                    #expect(values.isEmpty)
                } else {
                    throw TestError("Expected response based branching")
                }
            }
        }
    }
}

func loadFixture(_ name: String) throws -> Data {
    let url = Bundle.test.url(forResource: name, withExtension: "json")
    return try Data(contentsOf: url!)
}
