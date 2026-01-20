//
//  SurveySheet.swift
//  PostHog
//
//  Created by Ioannis Josephides on 12/03/2025.
//

#if os(iOS)

    import SwiftUI

    @available(iOS 15, *)
    struct SurveySheet: View {
        let survey: PostHogDisplaySurvey
        let isSurveyCompleted: Bool
        let currentQuestionIndex: Int
        let onClose: () -> Void
        let onNextQuestionClicked: (_ index: Int, _ response: PostHogSurveyResponse) -> Void

        @State private var sheetHeight: CGFloat = .zero

        var body: some View {
            surveyContent
                .animation(.linear(duration: 0.25), value: currentQuestionIndex)
                .readFrame(in: .named("survey-scroll-view")) { frame in
                    sheetHeight = frame.height
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SurveyDismissButton(action: onClose)
                    }
                }
                .surveyBottomSheet(height: sheetHeight)
                .environment(\.surveyAppearance, appearance)
        }

        @ViewBuilder
        private var surveyContent: some View {
            if isSurveyCompleted, appearance.displayThankYouMessage {
                ConfirmationMessage(onClose: onClose)
            } else if let currentQuestion {
                switch currentQuestion {
                case let currentQuestion as PostHogDisplayOpenQuestion:
                    OpenTextQuestionView(question: currentQuestion) { resp in
                        onNextQuestionClicked(currentQuestionIndex, .openEnded(resp))
                    }
                case let currentQuestion as PostHogDisplayLinkQuestion:
                    LinkQuestionView(question: currentQuestion) { resp in
                        onNextQuestionClicked(currentQuestionIndex, .link(resp))
                    }
                case let currentQuestion as PostHogDisplayRatingQuestion:
                    RatingQuestionView(question: currentQuestion) { resp in
                        onNextQuestionClicked(currentQuestionIndex, .rating(resp))
                    }
                case let currentQuestion as PostHogDisplayChoiceQuestion:
                    if currentQuestion.isMultipleChoice {
                        MultipleChoiceQuestionView(question: currentQuestion) { resp in
                            onNextQuestionClicked(currentQuestionIndex, .multipleChoice(resp))
                        }
                    } else {
                        SingleChoiceQuestionView(question: currentQuestion) { resp in
                            onNextQuestionClicked(currentQuestionIndex, .singleChoice(resp))
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }

        private var currentQuestion: PostHogDisplaySurveyQuestion? {
            guard currentQuestionIndex <= survey.questions.count - 1 else {
                return nil
            }
            return survey.questions[currentQuestionIndex]
        }

        private var appearance: SwiftUISurveyAppearance {
            .getAppearanceWithDefaults(survey.appearance)
        }
    }

    @available(iOS 15, *)
    private struct SurveyDismissButton: View {
        @Environment(\.surveyAppearance) private var appearance
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundColor(appearance.textColor ?? appearance.backgroundColor.getContrastingTextColor())
            }
            .buttonStyle(.borderless)
        }
    }

    extension View {
        @available(iOS 15, *)
        func surveyBottomSheet(height: CGFloat) -> some View {
            modifier(
                SurveyBottomSheetWithWithDetents(height: height)
            )
        }
    }

    @available(iOS 15.0, *)
    private struct SurveyBottomSheetWithWithDetents: ViewModifier {
        @Environment(\.surveyAppearance) private var appearance

        @State private var sheetHeight: CGFloat = .zero
        @State private var safeAreaInsetsTop: CGFloat = .zero

        let height: CGFloat

        func body(content: Content) -> some View {
            NavigationView {
                scrolledContent(with: content)
                    .background(appearance.backgroundColor)
                    .navigationBarTitleDisplayMode(.inline)
                    .readSafeAreaInsets { insets in
                        DispatchQueue.main.async {
                            if safeAreaInsetsTop == .zero {
                                safeAreaInsetsTop = insets.top
                            }
                        }
                    }
            }
            .interactiveDismissDisabled()
            .background(
                SurveyPresentationDetentsRepresentable(detents: sheetDetents)
            )
        }

        @ViewBuilder
        private func scrolledContent(with content: Content) -> some View {
            if #available(iOS 16.4, *) {
                ScrollView {
                    content
                        .padding(.horizontal, 16)
                }
                .coordinateSpace(name: "survey-scroll-view")
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, 16)
                }
                .coordinateSpace(name: "survey-scroll-view")
            }
        }

        private var sheetDetents: [SurveyPresentationDetentsRepresentable.Detent] {
            if adjustedSheetHeight >= UIScreen.main.bounds.height {
                return [.medium, .large]
            }
            return [.height(adjustedSheetHeight)]
        }

        var adjustedSheetHeight: CGFloat {
            height + safeAreaInsetsTop
        }
    }

    struct SwiftUISurveyAppearance {
        var fontFamily: Font
        var backgroundColor: Color
        var submitButtonColor: Color
        var submitButtonText: String
        var submitButtonTextColor: Color
        var textColor: Color?
        var descriptionTextColor: Color
        var ratingButtonColor: Color?
        var ratingButtonActiveColor: Color?
        var inputBackground: Color?
        var inputTextColor: Color?
        var displayThankYouMessage: Bool
        var thankYouMessageHeader: String
        var thankYouMessageDescription: String?
        var thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType = .text
        var thankYouMessageCloseButtonText: String
        var borderColor: Color
        var placeholder: String?
    }

    @available(iOS 15.0, *)
    private struct SurveyAppearanceEnvironmentKey: EnvironmentKey {
        static let defaultValue: SwiftUISurveyAppearance = .getAppearanceWithDefaults()
    }

    extension EnvironmentValues {
        @available(iOS 15.0, *)
        var surveyAppearance: SwiftUISurveyAppearance {
            get { self[SurveyAppearanceEnvironmentKey.self] }
            set { self[SurveyAppearanceEnvironmentKey.self] = newValue }
        }
    }

    extension SwiftUISurveyAppearance {
        @available(iOS 15.0, *)
        static func getAppearanceWithDefaults(_ appearance: PostHogDisplaySurveyAppearance? = nil) -> SwiftUISurveyAppearance {
            SwiftUISurveyAppearance(
                fontFamily: Font.customFont(family: appearance?.fontFamily ?? "") ?? Font.body,
                backgroundColor: colorFrom(css: appearance?.backgroundColor, defaultColor: .tertiarySystemBackground),
                submitButtonColor: colorFrom(css: appearance?.submitButtonColor, defaultColor: .black),
                submitButtonText: appearance?.submitButtonText ?? "Submit",
                submitButtonTextColor: colorFrom(css: appearance?.submitButtonTextColor, defaultColor: .white),
                textColor: colorFrom(css: appearance?.textColor),
                descriptionTextColor: colorFrom(css: appearance?.descriptionTextColor, defaultColor: .secondaryLabel),
                ratingButtonColor: colorFrom(css: appearance?.ratingButtonColor),
                ratingButtonActiveColor: colorFrom(css: appearance?.ratingButtonActiveColor),
                inputBackground: colorFrom(css: appearance?.inputBackground),
                inputTextColor: colorFrom(css: appearance?.inputTextColor),
                displayThankYouMessage: appearance?.displayThankYouMessage ?? true,
                thankYouMessageHeader: appearance?.thankYouMessageHeader ?? "Thank you for your feedback!",
                thankYouMessageDescriptionContentType: appearance?.thankYouMessageDescriptionContentType ?? .text,
                thankYouMessageCloseButtonText: appearance?.thankYouMessageCloseButtonText ?? "Close",
                borderColor: colorFrom(css: appearance?.borderColor, defaultColor: .systemFill)
            )
        }

        @available(iOS 15.0, *)
        private static func colorFrom(css hex: String?, defaultColor: UIColor) -> Color {
            guard let hex = hex, !hex.isEmpty else { return Color(uiColor: defaultColor) }
            return Color(uiColor: UIColor(hex: hex))
        }

        @available(iOS 15.0, *)
        private static func colorFrom(css hex: String?) -> Color? {
            guard let hex = hex, !hex.isEmpty else { return nil }
            return Color(uiColor: UIColor(hex: hex))
        }

        /// Computed input background color matching JS SDK behavior:
        /// - Use user-provided inputBackground if set
        /// - Otherwise use #f8f8f8 if survey background is white (for slight contrast)
        /// - Otherwise default to white
        @available(iOS 15.0, *)
        var effectiveInputBackground: Color {
            if let userInputBg = inputBackground {
                return userInputBg
            }
            if backgroundColor == Color.white || backgroundColor == Color(uiColor: .tertiarySystemBackground) {
                return Color(uiColor: UIColor(hex: "#f8f8f8"))
            }
            return .white
        }

        /// Computed input text color matching JS SDK behavior:
        /// - Use user-provided inputTextColor if set
        /// - Otherwise auto-contrast from effectiveInputBackground
        @available(iOS 15.0, *)
        var effectiveInputTextColor: Color {
            inputTextColor ?? effectiveInputBackground.getContrastingTextColor()
        }
    }

    @available(iOS 16.0, *)
    extension PresentationDetent {
        /// Same as .large detent but without shrinking the source view
        static let almostLarge = Self.custom(AlmostLarge.self)
    }

    @available(iOS 16.0, *)
    struct AlmostLarge: CustomPresentationDetent {
        static func height(in context: Context) -> CGFloat? {
            context.maxDetentValue - 0.5
        }
    }

    extension Font {
        static func customFont(family: String) -> Font? {
            if let uiFont = UIFont(name: family, size: UIFont.systemFontSize) {
                return Font(uiFont)
            }
            return nil
        }
    }

#endif
