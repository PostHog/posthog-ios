//
//  PostHogDisplaySurvey.swift
//  PostHog
//
//  Created by Ioannis Josephides on 18/06/2025.
//
#if os(iOS)
    import Foundation

    @objc public class PostHogDisplaySurvey: NSObject, Identifiable {
        public let id: String
        public let name: String
        public let questions: [PostHogDisplaySurveyQuestion]
        public let appearance: PostHogDisplaySurveyAppearance?
        public let startDate: Date?
        public let endDate: Date?

        init(
            id: String,
            name: String,
            questions: [PostHogDisplaySurveyQuestion],
            appearance: PostHogDisplaySurveyAppearance?,
            startDate: Date?,
            endDate: Date?
        ) {
            self.id = id
            self.name = name
            self.questions = questions
            self.appearance = appearance
            self.startDate = startDate
            self.endDate = endDate
            super.init()
        }
    }

    @objc public class PostHogNextSurveyQuestion: NSObject {
        public let questionIndex: Int
        public let isSurveyCompleted: Bool

        init(questionIndex: Int, isSurveyCompleted: Bool) {
            self.questionIndex = questionIndex
            self.isSurveyCompleted = isSurveyCompleted
            super.init()
        }
    }

    @objc public enum PostHogDisplaySurveyRatingType: Int {
        case number
        case emoji
    }

    @objc public enum PostHogDisplaySurveyTextContentType: Int {
        case html
        case text
    }

    @objc public class PostHogDisplaySurveyQuestion: NSObject {
        @objc public let question: String
        @objc public let questionDescription: String?
        @objc public let questionDescriptionContentType: PostHogDisplaySurveyTextContentType
        @objc public let optional: Bool
        @objc public let buttonText: String?

        init(
            question: String,
            questionDescription: String?,
            questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
            optional: Bool,
            buttonText: String?
        ) {
            self.question = question
            self.questionDescription = questionDescription
            self.questionDescriptionContentType = questionDescriptionContentType ?? .text
            self.optional = optional
            self.buttonText = buttonText
            super.init()
        }
    }

    @objc public class PostHogDisplayOpenQuestion: PostHogDisplaySurveyQuestion { /**/ }

    @objc public class PostHogDisplayLinkQuestion: PostHogDisplaySurveyQuestion {
        public let link: String?

        init(
            question: String,
            questionDescription: String?,
            questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
            optional: Bool,
            buttonText: String?,
            link: String?
        ) {
            self.link = link
            super.init(
                question: question,
                questionDescription: questionDescription,
                questionDescriptionContentType: questionDescriptionContentType,
                optional: optional,
                buttonText: buttonText
            )
        }
    }

    @objc public class PostHogDisplayRatingQuestion: PostHogDisplaySurveyQuestion {
        public let ratingType: PostHogDisplaySurveyRatingType
        public let ratingScale: Int
        public let lowerBoundLabel: String
        public let upperBoundLabel: String

        init(
            question: String,
            questionDescription: String?,
            questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
            optional: Bool,
            buttonText: String?,
            ratingType: PostHogDisplaySurveyRatingType,
            ratingScale: Int,
            lowerBoundLabel: String,
            upperBoundLabel: String
        ) {
            self.ratingType = ratingType
            self.ratingScale = ratingScale
            self.lowerBoundLabel = lowerBoundLabel
            self.upperBoundLabel = upperBoundLabel
            super.init(
                question: question,
                questionDescription: questionDescription,
                questionDescriptionContentType: questionDescriptionContentType,
                optional: optional,
                buttonText: buttonText
            )
        }
    }

    @objc public class PostHogDisplayChoiceQuestion: PostHogDisplaySurveyQuestion {
        public let choices: [String]
        public let hasOpenChoice: Bool
        public let shuffleOptions: Bool
        public let isMultipleChoice: Bool

        init(
            question: String,
            questionDescription: String?,
            questionDescriptionContentType: PostHogDisplaySurveyTextContentType?,
            optional: Bool,
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
                optional: optional,
                buttonText: buttonText
            )
        }
    }

    @objc public class PostHogDisplaySurveyAppearance: NSObject {
        // Layout
        public let fontFamily: String?

        // Colors
        public let backgroundColor: String?
        public let borderColor: String?

        // Submit button
        public let submitButtonColor: String?
        public let submitButtonText: String?
        public let submitButtonTextColor: String?

        // Text colors
        public let descriptionTextColor: String?

        // Rating buttons
        public let ratingButtonColor: String?
        public let ratingButtonActiveColor: String?

        // Input
        public let placeholder: String?

        // Thank you message
        public let displayThankYouMessage: Bool
        public let thankYouMessageHeader: String?
        public let thankYouMessageDescription: String?
        public let thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType?
        public let thankYouMessageCloseButtonText: String?

        init(
            fontFamily: String? = nil,
            backgroundColor: String? = nil,
            borderColor: String? = nil,
            submitButtonColor: String? = nil,
            submitButtonText: String? = nil,
            submitButtonTextColor: String? = nil,
            descriptionTextColor: String? = nil,
            ratingButtonColor: String? = nil,
            ratingButtonActiveColor: String? = nil,
            placeholder: String? = nil,
            displayThankYouMessage: Bool = true,
            thankYouMessageHeader: String? = nil,
            thankYouMessageDescription: String? = nil,
            thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType? = nil,
            thankYouMessageCloseButtonText: String? = nil
        ) {
            self.fontFamily = fontFamily
            self.backgroundColor = backgroundColor
            self.borderColor = borderColor
            self.submitButtonColor = submitButtonColor
            self.submitButtonText = submitButtonText
            self.submitButtonTextColor = submitButtonTextColor
            self.descriptionTextColor = descriptionTextColor
            self.ratingButtonColor = ratingButtonColor
            self.ratingButtonActiveColor = ratingButtonActiveColor
            self.placeholder = placeholder
            self.displayThankYouMessage = displayThankYouMessage
            self.thankYouMessageHeader = thankYouMessageHeader
            self.thankYouMessageDescription = thankYouMessageDescription
            self.thankYouMessageDescriptionContentType = thankYouMessageDescriptionContentType
            self.thankYouMessageCloseButtonText = thankYouMessageCloseButtonText
            super.init()
        }
    }
#endif
