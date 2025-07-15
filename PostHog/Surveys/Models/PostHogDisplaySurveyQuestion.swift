//
//  PostHogDisplaySurveyQuestion.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/06/2025.
//

import Foundation

/// Base class for all survey question types
@objc public class PostHogDisplaySurveyQuestion: NSObject {
    /// The main question text to display
    @objc public let question: String
    /// Optional additional description or context for the question
    @objc public let questionDescription: String?
    /// Content type for the question description (HTML or plain text)
    @objc public let questionDescriptionContentType: PostHogDisplaySurveyTextContentType
    /// Whether the question can be skipped
    @objc public let isOptional: Bool
    /// Optional custom text for the question's action button
    @objc public let buttonText: String?

    init(
        question: String,
        questionDescription: String?,
        questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
        isOptional: Bool,
        buttonText: String?
    ) {
        self.question = question
        self.questionDescription = questionDescription
        self.questionDescriptionContentType = questionDescriptionContentType ?? .text
        self.isOptional = isOptional
        self.buttonText = buttonText
        super.init()
    }
}

/// Represents an open-ended question where users can input free-form text
@objc public class PostHogDisplayOpenQuestion: PostHogDisplaySurveyQuestion { /**/ }

/// Represents a question with a clickable link
@objc public class PostHogDisplayLinkQuestion: PostHogDisplaySurveyQuestion {
    /// The URL that will be opened when the link is clicked
    public let link: String?

    init(
        question: String,
        questionDescription: String?,
        questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
        isOptional: Bool,
        buttonText: String?,
        link: String?
    ) {
        self.link = link
        super.init(
            question: question,
            questionDescription: questionDescription,
            questionDescriptionContentType: questionDescriptionContentType,
            isOptional: isOptional,
            buttonText: buttonText
        )
    }
}

/// Represents a rating question where users can select a rating from a scale
@objc public class PostHogDisplayRatingQuestion: PostHogDisplaySurveyQuestion {
    /// The type of rating scale (numbers, emoji)
    public let ratingType: PostHogDisplaySurveyRatingType
    /// The lower bound of the rating scale
    public let scaleLowerBound: Int
    /// The upper bound of the rating scale
    public let scaleUpperBound: Int
    /// The label for the lower bound of the rating scale
    public let lowerBoundLabel: String
    /// The label for the upper bound of the rating scale
    public let upperBoundLabel: String

    init(
        question: String,
        questionDescription: String?,
        questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
        isOptional: Bool,
        buttonText: String?,
        ratingType: PostHogDisplaySurveyRatingType,
        scaleLowerBound: Int,
        scaleUpperBound: Int,
        lowerBoundLabel: String,
        upperBoundLabel: String
    ) {
        self.ratingType = ratingType
        self.scaleLowerBound = scaleLowerBound
        self.scaleUpperBound = scaleUpperBound
        self.lowerBoundLabel = lowerBoundLabel
        self.upperBoundLabel = upperBoundLabel
        super.init(
            question: question,
            questionDescription: questionDescription,
            questionDescriptionContentType: questionDescriptionContentType,
            isOptional: isOptional,
            buttonText: buttonText
        )
    }
}

/// Represents a multiple or single choice question where users can select one or more options
@objc public class PostHogDisplayChoiceQuestion: PostHogDisplaySurveyQuestion {
    /// The list of options for the user to choose from
    public let choices: [String]
    /// Whether the question includes an "other" option for users to input free-form text
    public let hasOpenChoice: Bool
    /// Whether the options should be shuffled to randomize the order
    public let shuffleOptions: Bool
    /// Whether the user can select multiple options
    public let isMultipleChoice: Bool

    init(
        question: String,
        questionDescription: String?,
        questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
        isOptional: Bool,
        buttonText: String?,
        choices: [String],
        hasOpenChoice: Bool,
        shuffleOptions: Bool,
        isMultipleChoice: Bool
    ) {
        self.choices = choices
        self.hasOpenChoice = hasOpenChoice
        self.shuffleOptions = shuffleOptions
        self.isMultipleChoice = isMultipleChoice
        super.init(
            question: question,
            questionDescription: questionDescription,
            questionDescriptionContentType: questionDescriptionContentType,
            isOptional: isOptional,
            buttonText: buttonText
        )
    }
}
