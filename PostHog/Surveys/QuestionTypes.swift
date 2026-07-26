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

                textEditorView
                    .frame(height: 80)
                    .foregroundColor(inputTextColor)
                    .overlay(
                        Group {
                            if text.isEmpty {
                                Text(appearance.placeholder ?? "Start typing...")
                                    .foregroundColor(inputTextColor.opacity(0.5))
                                    .offset(x: 5, y: 8)
                            }
                        },
                        alignment: .topLeading
                    )
                    .padding(8)
                    .tint(inputTextColor)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(inputBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(appearance.borderColor, lineWidth: 1)
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

        private var inputBackground: Color {
            appearance.effectiveInputBackground
        }

        private var inputTextColor: Color {
            appearance.effectiveInputTextColor
        }

        @ViewBuilder
        private var textEditorView: some View {
            if #available(iOS 16.0, *) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
            } else {
                TextEditor(text: $text)
            }
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

        @State private var selectedChoices: Set<Int> = []
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
                    onNextQuestion(response)
                }
                .disabled(!canSubmit)
            }
        }

        private var response: String? {
            guard let index = selectedChoices.first, index < question.choices.count else { return nil }
            if index == openChoiceIndex(for: question) {
                return openChoiceInput.trimmingCharacters(in: .whitespaces)
            }
            return question.choices[index]
        }

        private var canSubmit: Bool {
            if question.isOptional { return true }
            return selectedChoices.count == 1 && (hasOpenChoiceSelected ? !openChoiceInput.isEmpty : true)
        }

        private var hasOpenChoiceSelected: Bool {
            isOpenChoiceSelected(in: selectedChoices, for: question)
        }
    }

    @available(iOS 15.0, *)
    struct MultipleChoiceQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogDisplayChoiceQuestion
        let onNextQuestion: ([String]?) -> Void

        @State private var selectedChoices: Set<Int> = []
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
                    onNextQuestion(response)
                }
                .disabled(!canSubmit)
            }
        }

        private var response: [String]? {
            let openIndex = openChoiceIndex(for: question)
            let resp = selectedChoices.sorted().compactMap { index -> String? in
                guard index < question.choices.count else { return nil }
                return index == openIndex ? openChoiceInput : question.choices[index]
            }
            return resp.isEmpty ? nil : resp
        }

        private var canSubmit: Bool {
            if question.isOptional { return true }
            return !selectedChoices.isEmpty && (hasOpenChoiceSelected ? !openChoiceInput.isEmpty : true)
        }

        private var hasOpenChoiceSelected: Bool {
            isOpenChoiceSelected(in: selectedChoices, for: question)
        }
    }

    private func openChoiceIndex(for question: PostHogDisplayChoiceQuestion) -> Int? {
        guard question.hasOpenChoice == true else { return nil }
        return question.choices.count - 1
    }

    private func isOpenChoiceSelected(in selectedChoices: Set<Int>, for question: PostHogDisplayChoiceQuestion) -> Bool {
        guard let openIndex = openChoiceIndex(for: question) else { return false }
        return selectedChoices.contains(openIndex)
    }
#endif
