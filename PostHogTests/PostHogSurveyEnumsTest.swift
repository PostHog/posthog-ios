//
//  PostHogSurveyEnumsTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 23/06/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Test Survey Enums")
struct PostHogSurveyEnumsTest {
    @Test("PostHogSurveyType handles unknown values")
    func surveyTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["popover", "api", "widget"]
        for typeString in knownTypes {
            let data = """
            "\(typeString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyType.self, from: data)

            switch typeString {
            case "popover":
                #expect(decodedType == .popover)
            case "api":
                #expect(decodedType == .api)
            case "widget":
                #expect(decodedType == .widget)
            default:
                throw TestError("Unexpected type string: \(typeString)")
            }
        }

        // Unknown value
        let unknownTypeString = "future_survey_type"
        let unknownData = """
        "\(unknownTypeString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyType.self, from: unknownData)

        if case let .unknown(type) = decodedUnknownType {
            #expect(type == unknownTypeString)
        } else {
            throw TestError("Expected unknown type")
        }
    }

    @Test("PostHogSurveyQuestionType handles unknown values")
    func surveyQuestionTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["open", "link", "rating", "multiple_choice", "single_choice"]
        for typeString in knownTypes {
            let data = """
            "\(typeString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyQuestionType.self, from: data)

            switch typeString {
            case "open":
                #expect(decodedType == .open)
            case "link":
                #expect(decodedType == .link)
            case "rating":
                #expect(decodedType == .rating)
            case "multiple_choice":
                #expect(decodedType == .multipleChoice)
            case "single_choice":
                #expect(decodedType == .singleChoice)
            default:
                throw TestError("Unexpected type string: \(typeString)")
            }
        }

        // Unknown value
        let unknownTypeString = "future_question_type"
        let unknownData = """
        "\(unknownTypeString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyQuestionType.self, from: unknownData)

        if case let .unknown(type) = decodedUnknownType {
            #expect(type == unknownTypeString)
        } else {
            throw TestError("Expected unknown type")
        }
    }

    @Test("PostHogSurveyTextContentType handles unknown values")
    func surveyTextContentTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["html", "text"]
        for typeString in knownTypes {
            let data = """
            "\(typeString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyTextContentType.self, from: data)

            switch typeString {
            case "html":
                #expect(decodedType == .html)
            case "text":
                #expect(decodedType == .text)
            default:
                throw TestError("Unexpected type string: \(typeString)")
            }
        }

        // Unknown value
        let unknownTypeString = "markdown"
        let unknownData = """
        "\(unknownTypeString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyTextContentType.self, from: unknownData)

        if case let .unknown(type) = decodedUnknownType {
            #expect(type == unknownTypeString)
        } else {
            throw TestError("Expected unknown type")
        }
    }

    @Test("PostHogSurveyMatchType handles unknown values")
    func surveyMatchTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["regex", "not_regex", "exact", "is_not", "icontains", "not_icontains"]
        for valueString in knownTypes {
            let data = """
            "\(valueString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyMatchType.self, from: data)

            switch valueString {
            case "regex":
                #expect(decodedType == .regex)
            case "not_regex":
                #expect(decodedType == .notRegex)
            case "exact":
                #expect(decodedType == .exact)
            case "is_not":
                #expect(decodedType == .isNot)
            case "icontains":
                #expect(decodedType == .iContains)
            case "not_icontains":
                #expect(decodedType == .notIContains)
            default:
                throw TestError("Unexpected value string: \(valueString)")
            }
        }

        // Unknown value
        let unknownValueString = "fuzzy_match"
        let unknownData = """
        "\(unknownValueString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyMatchType.self, from: unknownData)

        if case let .unknown(value) = decodedUnknownType {
            #expect(value == unknownValueString)
        } else {
            throw TestError("Expected unknown match type")
        }
    }

    @Test("PostHogSurveyAppearancePosition handles unknown values")
    func surveyAppearancePositionHandlesUnknownValues() throws {
        // Known values
        let knownPositions = ["left", "right", "center"]
        for positionString in knownPositions {
            let data = """
            "\(positionString)"
            """.data(using: .utf8)!

            let decodedPosition = try PostHogApi.jsonDecoder.decode(PostHogSurveyAppearancePosition.self, from: data)

            switch positionString {
            case "left":
                #expect(decodedPosition == .left)
            case "right":
                #expect(decodedPosition == .right)
            case "center":
                #expect(decodedPosition == .center)
            default:
                throw TestError("Unexpected position string: \(positionString)")
            }
        }

        // Unknown value
        let unknownPositionString = "bottom"
        let unknownData = """
        "\(unknownPositionString)"
        """.data(using: .utf8)!

        let decodedUnknownPosition = try PostHogApi.jsonDecoder.decode(PostHogSurveyAppearancePosition.self, from: unknownData)

        if case let .unknown(position) = decodedUnknownPosition {
            #expect(position == unknownPositionString)
        } else {
            throw TestError("Expected unknown position")
        }
    }

    @Test("PostHogSurveyAppearanceWidgetType handles unknown values")
    func surveyAppearanceWidgetTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["button", "tab", "selector"]
        for typeString in knownTypes {
            let data = """
            "\(typeString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyAppearanceWidgetType.self, from: data)

            switch typeString {
            case "button":
                #expect(decodedType == .button)
            case "tab":
                #expect(decodedType == .tab)
            case "selector":
                #expect(decodedType == .selector)
            default:
                throw TestError("Unexpected type string: \(typeString)")
            }
        }

        // Unknown value
        let unknownTypeString = "dropdown"
        let unknownData = """
        "\(unknownTypeString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyAppearanceWidgetType.self, from: unknownData)

        if case let .unknown(type) = decodedUnknownType {
            #expect(type == unknownTypeString)
        } else {
            throw TestError("Expected unknown widget type")
        }
    }

    @Test("PostHogSurveyRatingDisplayType handles unknown values")
    func surveyRatingDisplayTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["number", "emoji"]
        for typeString in knownTypes {
            let data = """
            "\(typeString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyRatingDisplayType.self, from: data)

            switch typeString {
            case "number":
                #expect(decodedType == .number)
            case "emoji":
                #expect(decodedType == .emoji)
            default:
                throw TestError("Unexpected type string: \(typeString)")
            }
        }

        // Unknown value
        let unknownTypeString = "stars"
        let unknownData = """
        "\(unknownTypeString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyRatingDisplayType.self, from: unknownData)

        if case let .unknown(type) = decodedUnknownType {
            #expect(type == unknownTypeString)
        } else {
            throw TestError("Expected unknown rating display type")
        }
    }

    @Test("PostHogSurveyRatingScale handles unknown values")
    func surveyRatingScaleHandlesUnknownValues() throws {
        // Known values
        let knownScales = [3, 5, 7, 10]
        for scale in knownScales {
            let data = "\(scale)".data(using: .utf8)!

            let decodedScale = try PostHogApi.jsonDecoder.decode(PostHogSurveyRatingScale.self, from: data)

            switch scale {
            case 3:
                #expect(decodedScale == .threePoint)
            case 5:
                #expect(decodedScale == .fivePoint)
            case 7:
                #expect(decodedScale == .sevenPoint)
            case 10:
                #expect(decodedScale == .tenPoint)
            default:
                throw TestError("Unexpected scale: \(scale)")
            }
        }

        // Unknown value
        let unknownScale = 4
        let unknownData = "\(unknownScale)".data(using: .utf8)!

        let decodedUnknownScale = try PostHogApi.jsonDecoder.decode(PostHogSurveyRatingScale.self, from: unknownData)

        if case let .unknown(scale) = decodedUnknownScale {
            #expect(scale == unknownScale)
        } else {
            throw TestError("Expected unknown scale")
        }
    }

    @Test("PostHogSurveyQuestionBranchingType handles unknown values")
    func surveyQuestionBranchingTypeHandlesUnknownValues() throws {
        // Known values
        let knownTypes = ["next_question", "end", "response_based", "specific_question"]
        for typeString in knownTypes {
            let data = """
            "\(typeString)"
            """.data(using: .utf8)!

            let decodedType = try PostHogApi.jsonDecoder.decode(PostHogSurveyQuestionBranchingType.self, from: data)

            switch typeString {
            case "next_question":
                #expect(decodedType == .nextQuestion)
            case "end":
                #expect(decodedType == .end)
            case "response_based":
                #expect(decodedType == .responseBased)
            case "specific_question":
                #expect(decodedType == .specificQuestion)
            default:
                throw TestError("Unexpected type string: \(typeString)")
            }
        }

        // Unknown value
        let unknownTypeString = "conditional_jump"
        let unknownData = """
        "\(unknownTypeString)"
        """.data(using: .utf8)!

        let decodedUnknownType = try PostHogApi.jsonDecoder.decode(PostHogSurveyQuestionBranchingType.self, from: unknownData)

        if case let .unknown(type) = decodedUnknownType {
            #expect(type == unknownTypeString)
        } else {
            throw TestError("Expected unknown branching type")
        }
    }
}
