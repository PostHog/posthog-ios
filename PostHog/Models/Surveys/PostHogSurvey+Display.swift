#if os(iOS) || TESTING
    import Foundation

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
                    scaleLowerBound: getRange(for: question.scale.rawValue, type: question.display).lowerBound,
                    scaleUpperBound: getRange(for: question.scale.rawValue, type: question.display).upperBound,
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
            }
        }

        private var isMultipleChoice: Bool {
            switch self {
            case .multipleChoice: return true
            default: return false
            }
        }

        private func getRange(for scale: Int, type ratingType: PostHogSurveyRatingDisplayType) -> ClosedRange<Int> {
            switch ratingType {
            case .emoji:
                scale == 3 ? 1 ... 3 : 1 ... 5
            case .number:
                switch scale {
                case 7: 1 ... 7
                case 10: 0 ... 10
                default: 1 ... 5
                }
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
