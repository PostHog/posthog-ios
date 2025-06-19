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

        let range: ClosedRange<Int>
        let lowerBoundLabel: String
        let upperBoundLabel: String

        var body: some View {
            VStack {
                HStack {
                    ForEach(range, id: \.self) { value in
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

                            if value != range.upperBound {
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
            if range.count == 3 {
                switch value {
                case 1: DissatisfiedEmoji().erasedToAnyView
                case 2: NeutralEmoji().erasedToAnyView
                case 3: SatisfiedEmoji().erasedToAnyView
                default: EmptyView().erasedToAnyView
                }
            } else if range.count == 5 {
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
                            range: 1 ... 5,
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
