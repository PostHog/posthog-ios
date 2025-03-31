//
//  EmojiRating.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct EmojiRating: View {
        @Environment(\.surveyAppearance) private var appearance
        @Binding var selectedValue: Int?

        let emojiRange: SurveyEmojiRange
        let lowerBoundLabel: String
        let upperBoundLabel: String

        var body: some View {
            VStack {
                HStack {
                    ForEach(emojiRange.range, id: \.self) { value in
                        Button {
                            withAnimation(.linear(duration: 0.25)) {
                                selectedValue = selectedValue == value ? nil : value
                            }
                        } label: {
                            let isSelected = selectedValue == value
                            emoji(for: value)
                                .frame(width: 48, height: 48)
                                .font(.body.bold())
                                .foregroundColor(foregroundColor(selected: isSelected))

                            if value != emojiRange.range.upperBound {
                                Spacer()
                            }
                        }
                    }
                }

                HStack(spacing: 0) {
                    Text(lowerBoundLabel)
                        .foregroundStyle(appearance.descriptionTextColor)
                        .frame(alignment: .leading)
                    Spacer()
                    Text(upperBoundLabel)
                        .foregroundStyle(appearance.descriptionTextColor)
                        .frame(alignment: .trailing)
                }
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        @ViewBuilder private func emoji(for value: Int) -> some View {
            if emojiRange.range.count == 3 {
                switch value {
                case 1: DissatisfiedEmoji().erasedToAnyView
                case 2: NeutralEmoji().erasedToAnyView
                case 3: SatisfiedEmoji().erasedToAnyView
                default: EmptyView().erasedToAnyView
                }
            } else if emojiRange.range.count == 5 {
                switch value {
                case 1: VeryDissatisfiedEmoji().erasedToAnyView
                case 2: DissatisfiedEmoji().erasedToAnyView
                case 3: NeutralEmoji().erasedToAnyView
                case 4: SatisfiedEmoji().erasedToAnyView
                case 5: VerySatisfiedEmoji().erasedToAnyView
                default: EmptyView().erasedToAnyView
                }
            }
        }

        private func foregroundColor(selected: Bool) -> Color {
            selected ? ratingButtonActiveColor : ratingButtonColor
        }

        private var ratingButtonColor: Color {
            appearance.ratingButtonColor ?? Color(uiColor: .tertiaryLabel)
        }

        private var ratingButtonActiveColor: Color {
            appearance.ratingButtonActiveColor ?? .black
        }
    }

    enum SurveyEmojiRange {
        case oneToThree
        case oneToFive

        var range: ClosedRange<Int> {
            switch self {
            case .oneToThree: 1 ... 3
            case .oneToFive: 1 ... 5
            }
        }
    }

    @available(iOS 18.0, *)
    #Preview {
        @Previewable @State var selectedValue: Int?

        NavigationView {
            VStack(spacing: 40) {
                EmojiRating(
                    selectedValue: $selectedValue,
                    emojiRange: .oneToFive,
                    lowerBoundLabel: "Unlikely",
                    upperBoundLabel: "Very likely"
                )
                .padding(.horizontal, 20)
            }
        }
        .navigationBarTitle(Text("Emoji Rating"))
        .environment(\.surveyAppearance.ratingButtonColor, .green.opacity(0.3))
        .environment(\.surveyAppearance.ratingButtonActiveColor, .green)
        .environment(\.surveyAppearance.descriptionTextColor, .orange)
    }

#endif
