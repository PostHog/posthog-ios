//
//  SurveyButton.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)

    import SwiftUI

    @available(iOS 15.0, *)
    struct SurveyButtonStyle: ButtonStyle {
        @Environment(\.surveyAppearance) private var appearance
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .shadow(color: Color.black.opacity(0.12), radius: 0, x: 0, y: -1) // Text shadow
                .padding(12)
                .foregroundStyle(appearance.submitButtonTextColor)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(appearance.submitButtonColor)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 2) // Box shadow
                )
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.80 : opacity)
        }

        private var opacity: Double {
            isEnabled ? 1.0 : 0.5
        }
    }
#endif
