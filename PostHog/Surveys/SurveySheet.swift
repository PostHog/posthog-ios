//
//  SurveySheet.swift
//  PostHog
//
//  Created by Ioannis Josephides on 12/03/2025.
//

#if os(iOS)

    import SwiftUI

    enum SurveyResponse {
        case link(String)
        case rating(Int)
        case openEnded(String)
        case singleChoice(String)
        case multipleChoice([String])
    }

    @available(iOS 15, *)
    struct SurveySheet: View {
        let survey: Survey
        let isSurveySent: Bool
        let currentQuestionIndex: Int?
        let onClose: () -> Void
        let onNextQuestionClicked: (_ index: Int, _ response: SurveyResponse) -> Void

        @State private var sheetHeight: CGFloat = .zero
        @State private var safeAreaInsets: EdgeInsets = .init()

        var body: some View {
            surveyContent
                .animation(.linear(duration: 0.25), value: currentQuestionIndex ?? 0)
                .readFrame(in: .named("survey-scroll-view")) { frame in
                    withAnimation {
                        sheetHeight = frame.height
                    }
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
            if isSurveySent, appearance.displayThankYouMessage {
                ConfirmationMessage(onClose: onClose)
            } else if let currentQuestion {
                switch currentQuestion {
                case let .open(openSurveyQuestion):
                    OpenTextQuestionView(question: openSurveyQuestion) { resp in
                        onNextQuestionClicked(0, .openEnded(resp))
                    }
                case let .link(linkSurveyQuestion):
                    LinkQuestionView(question: linkSurveyQuestion) { resp in
                        onNextQuestionClicked(0, .link(resp))
                    }
                case let .rating(ratingSurveyQuestion):
                    RatingQuestionView(question: ratingSurveyQuestion) { resp in
                        onNextQuestionClicked(0, .rating(resp))
                    }
                case let .singleChoice(multipleSurveyQuestion):
                    SingleChoiceQuestionView(question: multipleSurveyQuestion) { resp in
                        onNextQuestionClicked(0, .singleChoice(resp))
                    }
                case let .multipleChoice(multipleSurveyQuestion):
                    MultipleChoiceQuestionView(question: multipleSurveyQuestion) { resp in
                        onNextQuestionClicked(0, .multipleChoice(resp))
                    }
                }
            }
        }

        private var currentQuestion: SurveyQuestion? {
            guard let index = currentQuestionIndex, index <= survey.questions.count - 1 else {
                return nil
            }
            return survey.questions[index]
        }

        private var appearance: SurveyDisplayAppearance {
            .getAppearanceWithDefaults(survey.appearance)
        }
    }

    @available(iOS 15, *)
    private struct SurveyDismissButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundColor(Color(uiColor: .label))
            }
            .buttonStyle(.borderless)
        }
    }

    extension View {
        @ViewBuilder
        @available(iOS 15, *)
        func surveyBottomSheet(height: CGFloat) -> some View {
            if #available(iOS 16.4, *) {
                modifier(
                    SurveyBottomSheetWithDetents(height: height)
                )
            } else {
                NavigationView {
                    self
                }
            }
        }
    }

    @available(iOS 16.4, *)
    private struct SurveyBottomSheetWithDetents: ViewModifier {
        @Environment(\.surveyAppearance) private var appearance

        @State private var sheetHeight: CGFloat = .zero
        @State private var safeAreaInsetsTop: CGFloat = .zero

        let height: CGFloat

        func body(content: Content) -> some View {
            NavigationView {
                ScrollView {
                    content
                        .padding(.horizontal, 12)
                }
                .coordinateSpace(name: "survey-scroll-view")
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .readSafeAreaInsets { insets in
                    DispatchQueue.main.async {
                        if safeAreaInsetsTop == .zero {
                            safeAreaInsetsTop = insets.top
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
            .presentationDragIndicator(.automatic)
            .presentationContentInteraction(.resizes)
            .presentationDetents(sheetDetents)
            .presentationBackground(appearance.backgroundColor)
            .presentationBackgroundInteraction(.disabled)
        }

        var sheetDetents: Set<PresentationDetent> {
            let height = adjustedSheetHeight
            var detents = Set<PresentationDetent>()

            if height >= UIScreen.main.bounds.height / 2.0 {
                if height >= UIScreen.main.bounds.height {
                    detents.formUnion([.medium, .almostLarge])
                } else {
                    detents.formUnion([.medium, .height(height)])
                }
            } else {
                detents.insert(.height(height))
            }
            return detents
        }

        var adjustedSheetHeight: CGFloat {
            height + safeAreaInsetsTop
        }
    }

    struct SurveyDisplayAppearance {
        public var fontFamily: Font
        public var backgroundColor: Color
        public var submitButtonColor: Color
        public var submitButtonText: String
        public var submitButtonTextColor: Color
        public var descriptionTextColor: Color
        public var ratingButtonColor: Color?
        public var ratingButtonActiveColor: Color?
        public var displayThankYouMessage: Bool
        public var thankYouMessageHeader: String
        public var thankYouMessageDescription: String?
        public var thankYouMessageDescriptionContentType: SurveyTextContentType = .text
        public var thankYouMessageCloseButtonText: String
        public var borderColor: Color
        public var placeholder: String?
    }

    @available(iOS 15.0, *)
    private struct SurveyAppearanceEnvironmentKey: EnvironmentKey {
        static let defaultValue: SurveyDisplayAppearance = .getAppearanceWithDefaults()
    }

    extension EnvironmentValues {
        @available(iOS 15.0, *)
        var surveyAppearance: SurveyDisplayAppearance {
            get { self[SurveyAppearanceEnvironmentKey.self] }
            set { self[SurveyAppearanceEnvironmentKey.self] = newValue }
        }
    }

    extension SurveyDisplayAppearance {
        @available(iOS 15.0, *)
        static func getAppearanceWithDefaults(_ appearance: SurveyAppearance? = nil) -> SurveyDisplayAppearance {
            SurveyDisplayAppearance(
                fontFamily: Font.customFont(family: appearance?.fontFamily ?? "") ?? Font.body,
                backgroundColor: colorFrom(css: appearance?.backgroundColor, defaultColor: .tertiarySystemBackground),
                submitButtonColor: colorFrom(css: appearance?.submitButtonColor, defaultColor: .black),
                submitButtonText: appearance?.submitButtonText ?? "Submit",
                submitButtonTextColor: colorFrom(css: appearance?.submitButtonColor, defaultColor: .white),
                descriptionTextColor: colorFrom(css: appearance?.descriptionTextColor, defaultColor: .secondaryLabel),
                ratingButtonColor: colorFrom(css: appearance?.ratingButtonColor),
                ratingButtonActiveColor: colorFrom(css: appearance?.ratingButtonActiveColor),
                displayThankYouMessage: appearance?.displayThankYouMessage ?? true,
                thankYouMessageHeader: appearance?.thankYouMessageHeader ?? "Thank you for your feedback!",
                thankYouMessageDescriptionContentType: appearance?.thankYouMessageDescriptionContentType ?? .text,
                thankYouMessageCloseButtonText: appearance?.thankYouMessageCloseButtonText ?? "Close",
                borderColor: colorFrom(css: appearance?.borderColor, defaultColor: .systemFill)
            )
        }

        @available(iOS 15.0, *)
        private static func colorFrom(css hex: String?, defaultColor: UIColor) -> Color {
            hex.map { Color(uiColor: UIColor(hex: $0)) } ?? Color(uiColor: defaultColor)
        }

        @available(iOS 15.0, *)
        private static func colorFrom(css hex: String?) -> Color? {
            hex.map { Color(uiColor: UIColor(hex: $0)) }
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
