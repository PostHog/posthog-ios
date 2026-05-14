#if os(iOS) || TESTING
    import Foundation

    extension PostHogSurvey {
        func toDisplaySurvey(
            surveyTranslation: PostHogSurveyTranslation? = nil,
            questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil
        ) -> PostHogDisplaySurvey {
            let translatedQuestions = questions.enumerated().compactMap { index, question in
                question.toDisplayQuestion(translation: questionTranslations?[safe: index] ?? nil)
            }
            return PostHogDisplaySurvey(
                id: id,
                name: surveyTranslation?.name ?? name,
                questions: translatedQuestions,
                appearance: appearance?.toDisplayAppearance(translation: surveyTranslation),
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    private extension Array {
        subscript(safe index: Int) -> Element? {
            indices.contains(index) ? self[index] : nil
        }
    }

    extension PostHogSurveyQuestion {
        func toDisplayQuestion(translation: PostHogSurveyQuestionTranslation? = nil) -> PostHogDisplaySurveyQuestion? {
            switch self {
            case let .open(question):
                return PostHogDisplayOpenQuestion(
                    id: question.id,
                    question: translation?.question ?? question.question,
                    questionDescription: translation?.description ?? question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: translation?.buttonText ?? question.buttonText
                )

            case let .link(question):
                return PostHogDisplayLinkQuestion(
                    id: question.id,
                    question: translation?.question ?? question.question,
                    questionDescription: translation?.description ?? question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: translation?.buttonText ?? question.buttonText,
                    link: translation?.link ?? question.link ?? ""
                )

            case let .rating(question):
                return PostHogDisplayRatingQuestion(
                    id: question.id,
                    question: translation?.question ?? question.question,
                    questionDescription: translation?.description ?? question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: translation?.buttonText ?? question.buttonText,
                    ratingType: question.display.toDisplayRatingType(),
                    scaleLowerBound: question.scale.range.lowerBound,
                    scaleUpperBound: question.scale.range.upperBound,
                    lowerBoundLabel: translation?.lowerBoundLabel ?? question.lowerBoundLabel,
                    upperBoundLabel: translation?.upperBoundLabel ?? question.upperBoundLabel
                )

            case let .singleChoice(question), let .multipleChoice(question):
                return PostHogDisplayChoiceQuestion(
                    id: question.id,
                    question: translation?.question ?? question.question,
                    questionDescription: translation?.description ?? question.description,
                    questionDescriptionContentType: question.descriptionContentType?.toDisplayContentType(),
                    isOptional: question.optional ?? false,
                    buttonText: translation?.buttonText ?? question.buttonText,
                    choices: translation?.choices ?? question.choices,
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
        func toDisplayAppearance(translation: PostHogSurveyTranslation? = nil) -> PostHogDisplaySurveyAppearance {
            PostHogDisplaySurveyAppearance(
                fontFamily: fontFamily,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                submitButtonColor: submitButtonColor,
                submitButtonText: submitButtonText,
                submitButtonTextColor: submitButtonTextColor,
                textColor: textColor,
                descriptionTextColor: descriptionTextColor,
                ratingButtonColor: ratingButtonColor,
                ratingButtonActiveColor: ratingButtonActiveColor,
                inputBackground: inputBackground,
                inputTextColor: inputTextColor,
                placeholder: placeholder,
                surveyPopupDelaySeconds: surveyPopupDelaySeconds,
                displayThankYouMessage: displayThankYouMessage ?? true,
                thankYouMessageHeader: translation?.thankYouMessageHeader ?? thankYouMessageHeader,
                thankYouMessageDescription: translation?.thankYouMessageDescription ?? thankYouMessageDescription,
                thankYouMessageDescriptionContentType: thankYouMessageDescriptionContentType?.toDisplayContentType(),
                thankYouMessageCloseButtonText: translation?.thankYouMessageCloseButtonText ?? thankYouMessageCloseButtonText
            )
        }
    }
#endif
