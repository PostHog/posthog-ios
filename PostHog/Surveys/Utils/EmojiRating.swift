//
//  NumberRating.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    struct EmojiRating: View {
        @Binding var selectedValue: Int?
        let emojiRange: SurveyEmojiRange
        let lowerBoundLabel: String
        let upperBoundLabel: String

        var body: some View {
            VStack {
                HStack {
                    ForEach(emojiRange.range, id: \.self) { value in
                        Button(action: {
                            withAnimation(.linear(duration: 0.25)) {
                                selectedValue = selectedValue == value ? nil : value
                            }
                        }) {
                            let isSelected = selectedValue == value
                            emoji(for: value)
                                .frame(width: 48, height: 48)
                                .font(.body.bold())
                                .foregroundColor(isSelected ? Color.black : .gray.opacity(0.8))

                            if value != emojiRange.range.upperBound {
                                Spacer()
                            }
                        }
                    }
                }

                HStack(spacing: 0) {
                    Text(lowerBoundLabel).frame(alignment: .leading)
                    Spacer()
                    Text(upperBoundLabel).frame(alignment: .trailing)
                }
            }
        }

        @ViewBuilder
        private func emoji(for value: Int) -> some View {
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

    struct EmojiRatingPreview: View {
        @State private var selectedValue: Int?
        let range: SurveyEmojiRange

        var body: some View {
            EmojiRating(
                selectedValue: $selectedValue,
                emojiRange: range,
                lowerBoundLabel: "Unlikely",
                upperBoundLabel: "Very likely"
            )
        }
    }

    #Preview {
        NavigationView {
            VStack(spacing: 40) {
                EmojiRatingPreview(range: .oneToThree)
                    .padding(.horizontal, 20)
                EmojiRatingPreview(range: .oneToFive)
                    .padding(.horizontal, 20)
            }
        }
        .navigationBarTitle(Text("Emoji Rating"))
    }

#endif
