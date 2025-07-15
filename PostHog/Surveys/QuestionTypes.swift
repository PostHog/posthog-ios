//
//  QuestionTypes.swift
//  PostHog
//
//  Created by Ioannis Josephides on 13/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct OpenTextQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogDisplayOpenQuestion
        let onNextQuestion: (String?) -> Void

        @State private var text: String = ""

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.questionDescription,
                    contentType: question.questionDescriptionContentType
                )

                TextEditor(text: $text)
                    .frame(height: 80)
                    .overlay(
                        Group {
                            if text.isEmpty {
                                Text(appearance.placeholder ?? "Start typing...")
                                    .foregroundColor(.secondary)
                                    .offset(x: 5, y: 8)
                            }
                        },
                        alignment: .topLeading
                    )
                    .padding(8)
                    .tint(.black)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(uiColor: .secondaryLabel), lineWidth: 1)
                            .background(Color.white)
                    )

                BottomSection(label: question.buttonText ?? appearance.submitButtonText) {
                    let resp = text.trimmingCharacters(in: .whitespaces)
                    onNextQuestion(resp.isEmpty ? nil : text)
                }
                .disabled(!canSubmit)
            }
        }

        private var canSubmit: Bool {
            if question.isOptional { return true }
            return !text.isEmpty
        }
    }

    @available(iOS 15.0, *)
    struct LinkQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogDisplayLinkQuestion
        let onNextQuestion: (Bool) -> Void

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.questionDescription,
                    contentType: question.questionDescriptionContentType
                )

                BottomSection(label: question.buttonText ?? appearance.submitButtonText) {
                    onNextQuestion(true)
                    if let link, UIApplication.shared.canOpenURL(link) {
                        UIApplication.shared.open(link)
                    }
                }
            }
        }

        private var link: URL? {
            if let link = question.link {
                return URL(string: link)
            }
            return nil
        }
    }

    @available(iOS 15.0, *)
    struct RatingQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogDisplayRatingQuestion
        let onNextQuestion: (Int?) -> Void
        @State var rating: Int?

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.questionDescription,
                    contentType: question.questionDescriptionContentType
                )

                if question.ratingType == .emoji {
                    EmojiRating(
                        selectedValue: $rating,
                        scale: scale,
                        lowerBoundLabel: question.lowerBoundLabel,
                        upperBoundLabel: question.upperBoundLabel
                    )
                } else {
                    NumberRating(
                        selectedValue: $rating,
                        scale: scale,
                        lowerBoundLabel: question.lowerBoundLabel,
                        upperBoundLabel: question.upperBoundLabel
                    )
                }

                BottomSection(label: question.buttonText ?? appearance.submitButtonText) {
                    onNextQuestion(rating)
                }
                .disabled(!canSubmit)
            }
        }

        private var canSubmit: Bool {
            if question.isOptional { return true }
            return rating != nil
        }

        private var scale: PostHogSurveyRatingScale {
            PostHogSurveyRatingScale(range: question.scaleLowerBound ... question.scaleUpperBound)
        }
    }

    @available(iOS 15.0, *)
    struct SingleChoiceQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogDisplayChoiceQuestion
        let onNextQuestion: (String?) -> Void

        @State private var selectedChoices: Set<String> = []
        @State private var openChoiceInput: String = ""

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.questionDescription,
                    contentType: question.questionDescriptionContentType
                )

                MultipleChoiceOptions(
                    allowsMultipleSelection: false,
                    hasOpenChoiceQuestion: question.hasOpenChoice,
                    options: question.choices,
                    selectedOptions: $selectedChoices,
                    openChoiceInput: $openChoiceInput
                )

                BottomSection(label: question.buttonText ?? appearance.submitButtonText) {
                    let response = selectedChoices.first
                    let openChoiceInput = openChoiceInput.trimmingCharacters(in: .whitespaces)
                    onNextQuestion(response == openChoice ? openChoiceInput : response)
                }
                .disabled(!canSubmit)
            }
        }

        private var canSubmit: Bool {
            if question.isOptional { return true }
            return selectedChoices.count == 1 && (hasOpenChoiceSelected ? !openChoiceInput.isEmpty : true)
        }

        private var hasOpenChoiceSelected: Bool {
            guard let openChoice else { return false }
            return selectedChoices.contains(openChoice)
        }

        private var openChoice: String? {
            guard question.hasOpenChoice == true else { return nil }
            return question.choices.last
        }
    }

    @available(iOS 15.0, *)
    struct MultipleChoiceQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogDisplayChoiceQuestion
        let onNextQuestion: ([String]?) -> Void

        @State private var selectedChoices: Set<String> = []
        @State private var openChoiceInput: String = ""

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.questionDescription,
                    contentType: question.questionDescriptionContentType
                )

                MultipleChoiceOptions(
                    allowsMultipleSelection: true,
                    hasOpenChoiceQuestion: question.hasOpenChoice,
                    options: question.choices,
                    selectedOptions: $selectedChoices,
                    openChoiceInput: $openChoiceInput
                )

                BottomSection(label: question.buttonText ?? appearance.submitButtonText) {
                    let resp = selectedChoices.map { $0 == openChoice ? openChoiceInput : $0 }
                    onNextQuestion(resp.isEmpty ? nil : resp)
                }
                .disabled(!canSubmit)
            }
        }

        private var canSubmit: Bool {
            if question.isOptional { return true }
            return !selectedChoices.isEmpty && (hasOpenChoiceSelected ? !openChoiceInput.isEmpty : true)
        }

        private var hasOpenChoiceSelected: Bool {
            guard let openChoice else { return false }
            return selectedChoices.contains(openChoice)
        }

        private var openChoice: String? {
            guard question.hasOpenChoice == true else { return nil }
            return question.choices.last
        }
    }
#endif
