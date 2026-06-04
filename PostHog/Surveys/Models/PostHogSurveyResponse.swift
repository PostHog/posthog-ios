//
//  PostHogSurveyResponse.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/06/2025.
//

import Foundation

/// A model representing a user's response to a survey question
@objc @objcMembers
public class PostHogSurveyResponse: NSObject {
    /// The response kind: link, rating, open-ended, single-choice, or multiple-choice.
    public let type: PostHogSurveyResponseType
    /// Whether a link was clicked (for link questions)
    public let linkClicked: Bool?
    /// The numeric rating value (for rating questions)
    public let ratingValue: Int?
    /// The text response (for open questions)
    public let textValue: String?
    /// The selected options (for multiple or single choice questions)
    public let selectedOptions: [String]?

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
        selectedOptions = multipleChoiceValues
    }

    /// Creates a response for a link question.
    ///
    /// - Parameter clicked: Whether the link was clicked.
    /// - Returns: A response with type `.link` and `linkClicked` populated.
    public static func link(_ clicked: Bool) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .link,
            linkClicked: clicked,
            ratingValue: nil,
            textValue: nil,
            multipleChoiceValues: nil
        )
    }

    /// Creates a response for a rating question.
    ///
    /// - Parameter rating: The selected rating value.
    /// - Returns: A response with type `.rating` and `ratingValue` populated.
    public static func rating(_ rating: Int?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .rating,
            linkClicked: nil,
            ratingValue: rating,
            textValue: nil,
            multipleChoiceValues: nil
        )
    }

    /// Creates a response for an open-ended question.
    ///
    /// - Parameter openEnded: The text response.
    /// - Returns: A response with type `.openEnded` and `textValue` populated.
    public static func openEnded(_ openEnded: String?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .openEnded,
            linkClicked: nil,
            ratingValue: nil,
            textValue: openEnded,
            multipleChoiceValues: nil
        )
    }

    /// Creates a response for a single-choice question.
    ///
    /// - Parameter singleChoice: The selected option.
    /// - Returns: A response with type `.singleChoice` and `selectedOptions` containing the option when non-nil.
    public static func singleChoice(_ singleChoice: String?) -> PostHogSurveyResponse {
        PostHogSurveyResponse(
            type: .singleChoice,
            linkClicked: nil,
            ratingValue: nil,
            textValue: nil,
            multipleChoiceValues: {
                if let singleChoice { [singleChoice] } else { nil }
            }()
        )
    }

    /// Creates a response for a multiple-choice question.
    ///
    /// - Parameter multipleChoice: The selected options.
    /// - Returns: A response with type `.multipleChoice` and `selectedOptions` populated.
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

/// Type of response submitted for a survey question.
@objc public enum PostHogSurveyResponseType: Int {
    /// Response for a link question.
    case link
    /// Response for a rating question.
    case rating
    /// Response for an open-ended text question.
    case openEnded
    /// Response for a single-choice question.
    case singleChoice
    /// Response for a multiple-choice question.
    case multipleChoice
}
