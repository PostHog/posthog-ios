//
//  NumberRating.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    struct NumberRating: View {
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
                        .foregroundColor(selected ? Color.white : .black.opacity(0.5))
                } separatorView: { value, _ in
                    if value != numberRange.range.upperBound {
                        EdgeBorder(lineWidth: 1, edges: [.trailing]).foregroundColor(Color.gray)
                    }
                } indicatorView: { size in
                    Rectangle()
                        .fill(.black)
                        .frame(height: size.height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray, lineWidth: 2)
                )
                HStack {
                    Text(lowerBoundLabel).frame(alignment: .leading)
                    Spacer()
                    Text(upperBoundLabel).frame(alignment: .trailing)
                }
            }

            .padding(2)
        }
    }

    enum SurveyNumberRange {
        case oneToFive
        case oneToSeven
        case oneToTen

        var range: ClosedRange<Int> {
            switch self {
            case .oneToFive: 1 ... 5
            case .oneToSeven: 1 ... 7
            case .oneToTen: 0 ... 10
            }
        }
    }

    struct NumberRatingPreview: View {
        @State private var selectedValue: Int?
        let range: SurveyNumberRange

        var body: some View {
            NumberRating(
                selectedValue: $selectedValue,
                numberRange: range,
                lowerBoundLabel: "Unlikely",
                upperBoundLabel: "Very Likely"
            )
        }
    }

    #Preview {
        NavigationView {
            VStack(spacing: 15) {
                NumberRatingPreview(range: .oneToFive)
                    .padding()
                NumberRatingPreview(range: .oneToSeven)
                    .padding()
                NumberRatingPreview(range: .oneToTen)
                    .padding()
            }
        }
        .navigationBarTitle(Text("Number Rating"))
    }

#endif
