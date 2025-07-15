//
//  QuestionHeader.swift
//  PostHog
//
//  Created by Ioannis Josephides on 13/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct QuestionHeader: View {
        @Environment(\.surveyAppearance) private var appearance

        let question: String
        let description: String?
        let contentType: PostHogDisplaySurveyTextContentType

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(question)
                    .font(.body.bold())
                    .foregroundColor(foregroundTextColor)
                    .multilineTextAlignment(.leading)
                if let description, !description.isEmpty, contentType == .text {
                    Text(description)
                        .font(.callout)
                        .foregroundColor(foregroundTextColor)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var foregroundTextColor: Color {
            appearance.backgroundColor.getContrastingTextColor()
        }
    }

    @available(iOS 15.0, *)
    #Preview {
        QuestionHeader(
            question: "What can we do to improve our product?",
            description: "Any feedback will be helpful!",
            contentType: .text
        )
    }
#endif
