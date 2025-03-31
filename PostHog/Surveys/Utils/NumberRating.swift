//
//  NumberRating.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct NumberRating: View {
        @Environment(\.surveyAppearance) private var appearance

        @Binding var selectedValue: Int?
        let numberRange: SurveyNumberRange
        let lowerBoundLabel: String
        let upperBoundLabel: String

        var body: some View {
            VStack {
                SegmentedControl(
                    range: numberRange.range,
                    height: 45,
                    selectedValue: $selectedValue
                ) { value, selected in
                    Text("\(value)")
                        .font(.body.bold())
                        .foregroundColor(
                            foregroundTextColor(selected: selected)
                        )
                } separatorView: { value, _ in
                    if value != numberRange.range.upperBound {
                        EdgeBorder(lineWidth: 1, edges: [.trailing])
                            .foregroundStyle(appearance.borderColor)
                    }
                } indicatorView: { size in
                    Rectangle()
                        .fill(ratingButtonActiveColor)
                        .frame(height: size.height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .background(ratingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appearance.borderColor, lineWidth: 2)
                )
                HStack {
                    Text(lowerBoundLabel)
                        .font(.callout)
                        .foregroundColor(appearance.descriptionTextColor)
                        .frame(alignment: .leading)
                    Spacer()
                    Text(upperBoundLabel)
                        .font(.callout)
                        .foregroundColor(appearance.descriptionTextColor)
                        .frame(alignment: .trailing)
                }
            }

            .padding(2)
        }

        private func foregroundTextColor(selected: Bool) -> Color {
            backgroundColor(selected: selected)
                .getContrastingTextColor()
                .opacity(foregroundTextOpacity(selected: selected))
        }

        private func foregroundTextOpacity(selected: Bool) -> Double {
            selected ? 1 : 0.5
        }

        private func backgroundColor(selected: Bool) -> Color {
            selected ? ratingButtonActiveColor : ratingButtonColor
        }

        private var ratingButtonColor: Color {
            appearance.ratingButtonColor ?? Color(uiColor: .secondarySystemBackground)
        }

        private var ratingButtonActiveColor: Color {
            appearance.ratingButtonActiveColor ?? .black
        }
    }

    enum SurveyNumberRange {
        case oneToFive
        case oneToSeven
        case zeroToTen

        var range: ClosedRange<Int> {
            switch self {
            case .oneToFive: 1 ... 5
            case .oneToSeven: 1 ... 7
            case .zeroToTen: 0 ... 10
            }
        }
    }

    @available(iOS 18.0, *)
    #Preview {
        @Previewable @State var selectedValue: Int?

        NavigationView {
            VStack(spacing: 15) {
                NumberRating(
                    selectedValue: $selectedValue,
                    numberRange: .oneToFive,
                    lowerBoundLabel: "Unlikely",
                    upperBoundLabel: "Very Likely"
                )
            }
            .padding()
        }
        .navigationBarTitle(Text("Number Rating"))
        .environment(\.colorScheme, .light)
        // .environment(\.surveyAppearance.borderColor, .blue)
        // .environment(\.surveyAppearance.ratingButtonActiveColor, .white)
        // .environment(\.surveyAppearance.ratingButtonColor, .red)
    }

#endif
