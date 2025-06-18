//
//  PostHogSurveyEnums.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

// MARK: - Supporting Types

enum PostHogSurveyType: String, Decodable {
    case popover, api, widget
}

enum PostHogSurveyQuestionType: String, Decodable {
    case open
    case link
    case rating
    case multipleChoice = "multiple_choice"
    case singleChoice = "single_choice"
}

enum PostHogSurveyTextContentType: String, Decodable {
    case html, text
}

enum PostHogSurveyMatchType: String, Decodable {
    case regex
    case notRegex = "not_regex"
    case exact
    case isNot = "is_not"
    case iContains = "icontains"
    case notIContains = "not_icontains"
}

enum PostHogSurveyAppearancePosition: String, Decodable {
    case left, right, center
}

enum PostHogSurveyAppearanceWidgetType: String, Decodable {
    case button, tab, selector
}

enum PostHogSurveyRatingDisplayType: String, Decodable {
    case number, emoji
}

enum PostHogSurveyRatingScale: Int, Decodable {
    case threePoint = 3
    case fivePoint = 5
    case sevenPoint = 7
    case tenPoint = 10
}

enum PostHogSurveyQuestionBranchingType: String, Decodable {
    case nextQuestion = "next_question"
    case end
    case responseBased = "response_based"
    case specificQuestion = "specific_question"
}

@objc public enum PostHogSurveyResponseType: Int {
    case link
    case rating
    case openEnded
    case singleChoice
    case multipleChoice
}

@objc @objcMembers
public class PostHogSurveyResponse: NSObject {
    public let type: PostHogSurveyResponseType
    public let linkClicked: Bool?
    public let ratingValue: Int?
    public let textValue: String?
    public let multipleChoiceValues: [String]?

    private init(
        type: PostHogSurveyResponseType,
        linkClicked: Bool? = nil,
        ratingValue: Int? = nil,
        textValue: String? = nil,
        multipleChoiceValues: [String]? = nil
    ) {
        self.type = type
        self.linkClicked = linkClicked
        self.ratingValue = ratingValue
        self.textValue = textValue
        self.multipleChoiceValues = multipleChoiceValues
    }

    public static func link(_ clicked: Bool) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .link,
            linkClicked: clicked,
            ratingValue: nil,
            textValue: nil,
            multipleChoiceValues: nil
        )
    }

    public static func rating(_ rating: Int?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .rating,
            linkClicked: nil,
            ratingValue: rating,
            textValue: nil,
            multipleChoiceValues: nil
        )
    }

    public static func openEnded(_ openEnded: String?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .openEnded,
            linkClicked: nil,
            ratingValue: nil,
            textValue: openEnded,
            multipleChoiceValues: nil
        )
    }

    public static func singleChoice(_ singleChoice: String?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .singleChoice,
            linkClicked: nil,
            ratingValue: nil,
            textValue: singleChoice,
            multipleChoiceValues: nil
        )
    }

    public static func multipleChoice(_ multipleChoice: [String]?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .multipleChoice,
            linkClicked: nil,
            ratingValue: nil,
            textValue: nil,
            multipleChoiceValues: multipleChoice
        )
    }
}
