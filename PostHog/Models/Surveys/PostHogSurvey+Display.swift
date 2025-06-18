import Foundation

#if os(iOS)
    import PostHog

    extension PostHogSurvey {
        func toDisplaySurvey() -> PostHogDisplaySurvey {
            PostHogDisplaySurvey(
                id: id,
                name: name,
                questions: questions.map { $0.toDisplayQuestion() },
                appearance: appearance?.toDisplayAppearance(),
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    extension PostHogSurveyQuestion {
        func toDisplayQuestion() -> PostHogDisplaySurveyQuestion {
            switch self {
            case let .open(question):
                return PostHogDisplayOpenQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    optional: question.optional ?? false,
                    buttonText: question.buttonText
                )

            case let .link(question):
                return PostHogDisplayLinkQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    optional: question.optional ?? false,
                    buttonText: question.buttonText,
                    link: question.link ?? ""
                )

            case let .rating(question):
                return PostHogDisplayRatingQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    optional: question.optional ?? false,
                    buttonText: question.buttonText,
                    ratingType: question.display.toDisplayRatingType(),
                    ratingScale: question.scale.rawValue,
                    lowerBoundLabel: question.lowerBoundLabel,
                    upperBoundLabel: question.upperBoundLabel
                )

            case let .singleChoice(question), let .multipleChoice(question):
                return PostHogDisplayChoiceQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    optional: question.optional ?? false,
                    buttonText: question.buttonText,
                    choices: question.choices,
                    hasOpenChoice: question.hasOpenChoice ?? false,
                    shuffleOptions: question.shuffleOptions ?? false,
                    isMultipleChoice: isMultipleChoice
                )
            }
        }

        private var isMultipleChoice: Bool {
            switch self {
            case .multipleChoice: return true
            default: return false
            }
        }
    }

    extension PostHogSurveyTextContentType {
        func toDisplayContentType() -> PostHogDisplaySurveyTextContentType {
            switch self {
            case .html: return .html
            case .text: return .text
            }
        }
    }

    extension PostHogSurveyRatingDisplayType {
        func toDisplayRatingType() -> PostHogDisplaySurveyRatingType {
            switch self {
            case .number: return .number
            case .emoji: return .emoji
            }
        }
    }

    extension PostHogSurveyAppearance {
        func toDisplayAppearance() -> PostHogDisplaySurveyAppearance {
            PostHogDisplaySurveyAppearance(
                fontFamily: fontFamily,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                submitButtonColor: submitButtonColor,
                submitButtonText: submitButtonText,
                submitButtonTextColor: submitButtonTextColor,
                descriptionTextColor: descriptionTextColor,
                ratingButtonColor: ratingButtonColor,
                ratingButtonActiveColor: ratingButtonActiveColor,
                placeholder: placeholder,
                displayThankYouMessage: displayThankYouMessage ?? true,
                thankYouMessageHeader: thankYouMessageHeader,
                thankYouMessageDescription: thankYouMessageDescription,
                thankYouMessageCloseButtonText: thankYouMessageCloseButtonText
            )
        }
    }
#endif
