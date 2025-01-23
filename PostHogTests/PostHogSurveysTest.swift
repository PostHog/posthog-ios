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
        private func loadFixture(_ name: String) throws -> Data {
            let url = Bundle.test.url(forResource: name, withExtension: "json")
            return try Data(contentsOf: #require(url))
        }

        @Test("Survey decodes correctly")
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

        @Test("Survey question types decode correctly")
        func surveyQuestionTypesDecodeCorrectly() throws {
            let data = try loadFixture("fixture_survey_question_types")
            let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

            // Basic question
            if case let .basic(question) = sut.questions[0] {
                #expect(question.question == "What would you like to see in our Core Web Vitals product?")
                #expect(question.description == "Core Web Vitals just launched and we're interested in hearing (reading?) from you on what you think we're missing with this product")
                #expect(question.descriptionContentType == .text)
                #expect(question.originalQuestionIndex == 0)
            } else {
                throw TestError("Expected a basic question")
            }

            // Single-choice Question
            if case let .singleChoice(question) = sut.questions[1] {
                #expect(question.choices == ["Heck yeah", "Nope, I'm good"])
                #expect(question.question == "Would you be interested in being part of a PostHog community event in your city?")
                #expect(question.buttonText == "Submit")
                #expect(question.originalQuestionIndex == 0)
                #expect(question.descriptionContentType == .text)
            } else {
                throw TestError("Expected a single choice question")
            }

            // Multiple Choice Question
            if case let .multipleChoice(question) = sut.questions[2] {
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

            // Link Question
            if case let .link(question) = sut.questions[3] {
                #expect(question.link == "https://cal.com/david-posthog/user-interview")
                #expect(question.question == "Share your thoughts")
                #expect(question.buttonText == "Schedule")
                #expect(question.description == "We'd love to get your first impressions of the feature on a video call")
            } else {
                throw TestError("Expected a link question")
            }

            // Rating Question
            if case let .rating(question) = sut.questions[4] {
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

        @Test("Survey question branching decodes correctly")
        func surveyQuestionBranchingDecodesCorrectly() throws {
            let data = try loadFixture("fixture_survey_branching")
            let sut = try PostHogApi.jsonDecoder.decode(Survey.self, from: data)

            // Check question and branching types
            if case let .singleChoice(question) = sut.questions[0] {
                if case .next = question.branching {} else {
                    throw TestError("Expected next question branching")
                }
            } else {
                throw TestError("Expected single choice question")
            }

            if case let .singleChoice(question) = sut.questions[1] {
                if case .end = question.branching {} else {
                    throw TestError("Expected end branching")
                }
            } else {
                throw TestError("Expected single choice question")
            }

            if case let .singleChoice(question) = sut.questions[2] {
                if case let .specificQuestion(index: index) = question.branching {
                    #expect(index == 2)
                } else {
                    throw TestError("Expected specific question branching")
                }
            } else {
                throw TestError("Expected single choice question")
            }

            if case let .rating(question) = sut.questions[3] {
                if case let .responseBased(values) = question.branching {
                    #expect(values["0"] as? Int == 1)
                    #expect(values["1"] as? String == "end")
                } else {
                    throw TestError("Expected response based branching")
                }
            } else {
                throw TestError("Expected rating question")
            }

            if case let .rating(question) = sut.questions[4] {
                if case let .responseBased(values) = question.branching {
                    #expect(values["negative"] as? Int == 1)
                    #expect(values["neutral"] as? Int == 2)
                    #expect(values["positive"] as? Int == 3)
                } else {
                    throw TestError("Expected response based branching")
                }
            } else {
                throw TestError("Expected rating question")
            }

            if case let .singleChoice(question) = sut.questions[5] {
                if case let .responseBased(values) = question.branching {
                    #expect(values.isEmpty)
                } else {
                    throw TestError("Expected response based branching")
                }
            } else {
                throw TestError("Expected single choice question")
            }
        }
    }
}
