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

        let question: PostHogOpenSurveyQuestion
        let onNextQuestion: (String?) -> Void

        @State private var text: String = ""

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.description,
                    contentType: question.descriptionContentType ?? .text
                )

                TextEditor(text: $text)
                    .frame(height: 150)
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
            if question.optional == true { return true }
            return !text.isEmpty
        }
    }

    @available(iOS 15.0, *)
    struct LinkQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogLinkSurveyQuestion
        let onNextQuestion: (String) -> Void

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.description,
                    contentType: question.descriptionContentType ?? .text
                )

                BottomSection(label: question.buttonText ?? appearance.submitButtonText) {
                    onNextQuestion("link clicked")
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

        let question: PostHogRatingSurveyQuestion
        let onNextQuestion: (Int?) -> Void
        @State var rating: Int?

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.description,
                    contentType: question.descriptionContentType ?? .text
                )

                if question.display == .emoji {
                    EmojiRating(
                        selectedValue: $rating,
                        emojiRange: emojiRange,
                        lowerBoundLabel: question.lowerBoundLabel,
                        upperBoundLabel: question.upperBoundLabel
                    )
                } else {
                    NumberRating(
                        selectedValue: $rating,
                        numberRange: numberRange,
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
            if question.optional == true { return true }
            return rating != nil
        }

        private var emojiRange: SurveyEmojiRange {
            question.scale == .threePoint ? .oneToThree : .oneToFive
        }

        private var numberRange: SurveyNumberRange {
            switch question.scale {
            case .sevenPoint: .oneToSeven
            case .tenPoint: .zeroToTen
            default: .oneToFive
            }
        }
    }

    @available(iOS 15.0, *)
    struct SingleChoiceQuestionView: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: PostHogMultipleSurveyQuestion
        let onNextQuestion: (String?) -> Void

        @State private var selectedChoices: Set<String> = []
        @State private var openChoiceInput: String = ""

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.description,
                    contentType: question.descriptionContentType ?? .text
                )

                MultipleChoiceOptions(
                    allowsMultipleSelection: false,
                    hasOpenChoiceQuestion: question.hasOpenChoice ?? false,
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
            if question.optional == true { return true }
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

        let question: PostHogMultipleSurveyQuestion
        let onNextQuestion: ([String]?) -> Void

        @State private var selectedChoices: Set<String> = []
        @State private var openChoiceInput: String = ""

        var body: some View {
            VStack(spacing: 16) {
                QuestionHeader(
                    question: question.question,
                    description: question.description,
                    contentType: question.descriptionContentType ?? .text
                )

                MultipleChoiceOptions(
                    allowsMultipleSelection: true,
                    hasOpenChoiceQuestion: question.hasOpenChoice ?? false,
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
            if question.optional == true { return true }
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
