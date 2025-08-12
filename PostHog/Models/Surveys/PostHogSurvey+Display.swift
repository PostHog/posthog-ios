#if os(iOS) || TESTING
    import Foundation

    extension PostHogSurvey {
        func toDisplaySurvey() -> PostHogDisplaySurvey {
            PostHogDisplaySurvey(
                id: id,
                name: name,
                questions: questions.compactMap { $0.toDisplayQuestion() },
                appearance: appearance?.toDisplayAppearance(),
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    extension PostHogSurveyQuestion {
        func toDisplayQuestion() -> PostHogDisplaySurveyQuestion? {
            switch self {
            case let .open(question):
                return PostHogDisplayOpenQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: question.buttonText
                )

            case let .link(question):
                return PostHogDisplayLinkQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: question.buttonText,
                    link: question.link ?? ""
                )

            case let .rating(question):
                return PostHogDisplayRatingQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: question.buttonText,
                    ratingType: question.display.toDisplayRatingType(),
                    scaleLowerBound: question.scale.range.lowerBound,
                    scaleUpperBound: question.scale.range.upperBound,
                    lowerBoundLabel: question.lowerBoundLabel,
                    upperBoundLabel: question.upperBoundLabel
                )

            case let .singleChoice(question), let .multipleChoice(question):
                return PostHogDisplayChoiceQuestion(
                    question: question.question,
                    questionDescription: question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: question.buttonText,
                    choices: question.choices,
                    hasOpenChoice: question.hasOpenChoice ?? false,
                    shuffleOptions: question.shuffleOptions ?? false,
                    isMultipleChoice: isMultipleChoice
                )

            default:
                return nil
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
            if case .html = self {
                return .html
            }
            return .text
        }
    }

    extension PostHogSurveyRatingDisplayType {
        func toDisplayRatingType() -> PostHogDisplaySurveyRatingType {
            if case .emoji = self {
                return .emoji
            }
            return .number
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
                thankYouMessageDescriptionContentType: thankYouMessageDescriptionContentType?.toDisplayContentType(),
                thankYouMessageCloseButtonText: thankYouMessageCloseButtonText
            )
        }
    }
#endif
