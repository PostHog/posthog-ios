//
//  ConfirmationMessage.swift
//  PostHog
//
//  Created by Ioannis Josephides on 13/03/2025.
//

#if os(iOS) && (!SWIFT_PACKAGE || Surveys)
    import SwiftUI

    struct ConfirmationMessage: View {
        @Environment(\.surveyAppearance) private var appearance

        let onClose: () -> Void

        var body: some View {
            VStack(spacing: 16) {
                Text(appearance.thankYouMessageHeader)
                    .surveyFont(.body, bold: true)
                    .foregroundStyle(foregroundTextColor)
                if let description = appearance.thankYouMessageDescription, appearance.thankYouMessageDescriptionContentType == .text {
                    Text(description)
                        .surveyFont(.body)
                        .foregroundStyle(foregroundTextColor)
                }

                BottomSection(label: appearance.thankYouMessageCloseButtonText, action: onClose)
                    .padding(.top, 20)
            }
        }

        private var foregroundTextColor: Color {
            appearance.textColor ?? appearance.backgroundColor.getContrastingTextColor()
        }
    }

    #Preview {
        ConfirmationMessage {}
    }
#endif
