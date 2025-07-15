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

        let scale: PostHogSurveyRatingScale
        let lowerBoundLabel: String
        let upperBoundLabel: String

        var body: some View {
            VStack {
                HStack {
                    ForEach(scale.range, id: \.self) { value in
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

                            if value != scale.range.upperBound {
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
            switch scale {
            case .threePoint:
                switch value {
                case 1: DissatisfiedEmoji()
                case 2: NeutralEmoji()
                case 3: SatisfiedEmoji()
                default: EmptyView()
                }
            case .fivePoint:
                switch value {
                case 1: VeryDissatisfiedEmoji()
                case 2: DissatisfiedEmoji()
                case 3: NeutralEmoji()
                case 4: SatisfiedEmoji()
                case 5: VerySatisfiedEmoji()
                default: EmptyView()
                }
            default: EmptyView()
            }
        }

        private func foregroundColor(selected: Bool) -> Color {
            selected ? Color(uiColor: .label) : Color(uiColor: .tertiaryLabel)
        }

        private var ratingButtonActiveColor: Color {
            appearance.ratingButtonActiveColor ?? .black
        }
    }

    #if DEBUG
        @available(iOS 18.0, *)
        private struct TestView: View {
            @State var selectedValue: Int?

            var body: some View {
                NavigationView {
                    VStack(spacing: 40) {
                        EmojiRating(
                            selectedValue: $selectedValue,
                            scale: .fivePoint,
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
        }

        @available(iOS 18.0, *)
        #Preview {
            TestView()
        }
    #endif
#endif
