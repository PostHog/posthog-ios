//
//  PostHogSurveysConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/04/2025.
//

#if os(iOS)
    import Foundation

    @objc public enum PostHogDisplaySurveyRatingType: Int {
        case number
        case emoji
    }

    @objc public class PostHogDisplaySurveyQuestion: NSObject {
        public let question: String
        public let questionDescription: String?
        public let optional: Bool
        public let buttonText: String?

        init(
            question: String,
            questionDescription: String?,
            optional: Bool,
            buttonText: String?
        ) {
            self.question = question
            self.questionDescription = questionDescription
            self.optional = optional
            self.buttonText = buttonText
            super.init()
        }
    }

    @objc public class PostHogDisplayOpenQuestion: PostHogDisplaySurveyQuestion {}

    @objc public class PostHogDisplayLinkQuestion: PostHogDisplaySurveyQuestion {
        public let link: String

        init(
            question: String,
            questionDescription: String?,
            optional: Bool,
            buttonText: String?,
            link: String
        ) {
            self.link = link
            super.init(question: question, questionDescription: questionDescription, optional: optional, buttonText: buttonText)
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
            super.init(question: question, questionDescription: questionDescription, optional: optional, buttonText: buttonText)
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
            super.init(question: question, questionDescription: questionDescription, optional: optional, buttonText: buttonText)
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
        public let ratingButtonHoverColor: String?

        // Input
        public let placeholder: String?

        // Thank you message
        public let displayThankYouMessage: Bool
        public let thankYouMessageHeader: String?
        public let thankYouMessageDescription: String?
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
            ratingButtonHoverColor: String? = nil,
            placeholder: String? = nil,
            displayThankYouMessage: Bool = true,
            thankYouMessageHeader: String? = nil,
            thankYouMessageDescription: String? = nil,
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
            self.ratingButtonHoverColor = ratingButtonHoverColor
            self.placeholder = placeholder
            self.displayThankYouMessage = displayThankYouMessage
            self.thankYouMessageHeader = thankYouMessageHeader
            self.thankYouMessageDescription = thankYouMessageDescription
            self.thankYouMessageCloseButtonText = thankYouMessageCloseButtonText
            super.init()
        }
    }

    @objc public class PostHogSurveysConfig: NSObject {
        public var surveysDelegate: PostHogSurveysDelegate?
    }

    @objc public protocol PostHogSurveysDelegate {
        @objc func renderSurvey(
            _ survey: PostHogDisplaySurvey,
            onSurveyShown: @escaping OnSurveyDelegateShown,
            onSurveyResponse: @escaping OnSurveyDelegateResponse,
            onSurveyClosed: @escaping OnSurveyDelegateClosed
        )
    }

    @objc public class PostHogDisplaySurvey: NSObject {
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

    public typealias OnSurveyDelegateShown = (_ survey: PostHogDisplaySurvey) -> Void
    public typealias OnSurveyDelegateResponse = (_ survey: PostHogDisplaySurvey, _ index: Int, _ response: String) -> PostHogNextSurveyQuestion
    public typealias OnSurveyDelegateClosed = (_ survey: PostHogDisplaySurvey) -> Void

    /// Temporary struct for creating dummy surveys for testing purposes
    enum DummyPostHogSurveys {
        static var dummyAppearance: PostHogDisplaySurveyAppearance {
            PostHogDisplaySurveyAppearance(
                backgroundColor: "#FFFFFF",
                submitButtonColor: "#000000",
                submitButtonText: "Submit",
                submitButtonTextColor: "#FFFFFF",
                ratingButtonColor: "#E5E5E5",
                ratingButtonActiveColor: "#000000",
                thankYouMessageHeader: "Thank you for your feedback!",
                thankYouMessageDescription: "Your feedback is valuable to us."
            )
        }

        static var openQuestion: PostHogDisplaySurvey {
            let question1 = PostHogDisplayOpenQuestion(
                question: "How can we improve our app?",
                questionDescription: "Please share your thoughts with us",
                optional: false,
                buttonText: "Submit Feedback"
            )
            let question2 = PostHogDisplayOpenQuestion(
                question: "Anything else you'd like to add?",
                questionDescription: "Please share your thoughts with us",
                optional: false,
                buttonText: "Submit Feedback"
            )

            return PostHogDisplaySurvey(
                id: "dummy-open",
                name: "Feedback Survey",
                questions: [question1, question2],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }

        static var linkQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayLinkQuestion(
                question: "Are you interested to join our webinar?",
                questionDescription: "Please follow the link below to book your spot",
                optional: false,
                buttonText: "Book Now",
                link: "http://www.google.com"
            )

            return PostHogDisplaySurvey(
                id: "dummy-open",
                name: "Feedback Survey",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }

        static var ratingNumberQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayRatingQuestion(
                question: "How would you rate our app?",
                questionDescription: "Rate us from 1 to 5",
                optional: false,
                buttonText: "Submit Rating",
                ratingType: .number,
                ratingScale: 5,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )

            return PostHogDisplaySurvey(
                id: "dummy-rating",
                name: "App Rating",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var ratingFiveEmojiQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayRatingQuestion(
                question: "How would you rate our app?",
                questionDescription: "Rate us from 1 to 5",
                optional: false,
                buttonText: "Submit Rating",
                ratingType: .emoji,
                ratingScale: 5,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )

            return PostHogDisplaySurvey(
                id: "dummy-rating",
                name: "App Rating",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var ratingThreeEmojiQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayRatingQuestion(
                question: "How would you rate our app?",
                questionDescription: "Rate us from 1 to 3",
                optional: false,
                buttonText: "Submit Rating",
                ratingType: .emoji,
                ratingScale: 3,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )

            return PostHogDisplaySurvey(
                id: "dummy-rating",
                name: "App Rating",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var ratingFiveQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayRatingQuestion(
                question: "How would you rate our app?",
                questionDescription: "Rate us from 1 to 5",
                optional: false,
                buttonText: "Submit Rating",
                ratingType: .number,
                ratingScale: 5,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )

            return PostHogDisplaySurvey(
                id: "dummy-rating",
                name: "App Rating",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var ratingSevenQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayRatingQuestion(
                question: "How would you rate our app?",
                questionDescription: "Rate us from 1 to 7",
                optional: false,
                buttonText: "Submit Rating",
                ratingType: .number,
                ratingScale: 7,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )

            return PostHogDisplaySurvey(
                id: "dummy-rating",
                name: "App Rating",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var ratingTenQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayRatingQuestion(
                question: "How would you rate our app?",
                questionDescription: "Rate us from 1 to 10",
                optional: false,
                buttonText: "Submit Rating",
                ratingType: .number,
                ratingScale: 10,
                lowerBoundLabel: "Poor",
                upperBoundLabel: "Excellent"
            )

            return PostHogDisplaySurvey(
                id: "dummy-rating",
                name: "App Rating",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }

        static var multipleChoiceQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayChoiceQuestion(
                question: "What features would you like to see?",
                questionDescription: "Select all that apply",
                optional: false,
                buttonText: "Submit Choices",
                choices: ["Dark Mode", "Offline Support", "Push Notifications", "Cloud Sync"],
                hasOpenChoice: true,
                shuffleOptions: false,
                isMultipleChoice: true
            )

            return PostHogDisplaySurvey(
                id: "dummy-multiple",
                name: "Feature Request",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }

        static var singleChoiceQuestion: PostHogDisplaySurvey {
            let question = PostHogDisplayChoiceQuestion(
                question: "What features would you like to see?",
                questionDescription: "Select one option",
                optional: false,
                buttonText: "Submit Choices",
                choices: ["Dark Mode", "Offline Support", "Push Notifications", "Cloud Sync"],
                hasOpenChoice: false,
                shuffleOptions: false,
                isMultipleChoice: false
            )

            return PostHogDisplaySurvey(
                id: "dummy-multiple",
                name: "Feature Request",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var singleChoiceQuestionWithOpenChoice: PostHogDisplaySurvey {
            let question = PostHogDisplayChoiceQuestion(
                question: "What features would you like to see?",
                questionDescription: "Select one",
                optional: false,
                buttonText: "Submit Choices",
                choices: [
                    "Dark Mode",
                    "Offline Support",
                    "Push Notifications",
                    "Deep Links",
                    "Live Activities",
                    "Localization",
                    "Cloud Sync",
                    "More Option",
                    "More Option 2",
                    "More Option 3",
                    "More Option 4",
                    "More Option 5",
                    "More Option 6",
                    "More Option 7",
                    "Other"],
                hasOpenChoice: true,
                shuffleOptions: false,
                isMultipleChoice: false
            )

            return PostHogDisplaySurvey(
                id: "dummy-multiple",
                name: "Feature Request",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
        
        static var multipleChoiceQuestionWithOpenChoice: PostHogDisplaySurvey {
            let question = PostHogDisplayChoiceQuestion(
                question: "What features would you like to see?",
                questionDescription: "Select many",
                optional: false,
                buttonText: "Submit Choices",
                choices: [
                    "Dark Mode",
                    "Offline Support",
                    "Push Notifications",
                    "Deep Links",
                    "Live Activities",
                    "Localization",
                    "Cloud Sync",
                    "More Option",
                    "More Option 2",
                    "More Option 3",
                    "More Option 4",
                    "More Option 5",
                    "More Option 6",
                    "More Option 7",
                    "Other"],
                hasOpenChoice: true,
                shuffleOptions: false,
                isMultipleChoice: true
            )

            return PostHogDisplaySurvey(
                id: "dummy-multiple",
                name: "Feature Request",
                questions: [question],
                appearance: dummyAppearance,
                startDate: Date(),
                endDate: nil
            )
        }
    }
#endif
