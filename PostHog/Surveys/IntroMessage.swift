//
//  IntroMessage.swift
//  PostHog
//
//  Created by PostHog Code on 2026-08-06.
//

#if os(iOS)
    import SwiftUI

    /// Optional intro screen shown before the first question — the leading mirror of the
    /// trailing `ConfirmationMessage`. Advancing records no response and sends no survey event.
    @available(iOS 15.0, *)
    struct IntroMessage: View {
        @Environment(\.surveyAppearance) private var appearance

        let onStart: () -> Void

        var body: some View {
            VStack(spacing: 16) {
                if !appearance.introScreenHeader.isEmpty {
                    Text(appearance.introScreenHeader)
                        .font(.body.bold())
                        .foregroundStyle(foregroundTextColor)
                }
                if let description = appearance.introScreenDescription, appearance.introScreenDescriptionContentType == .text {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(foregroundTextColor)
                }

                BottomSection(label: appearance.introScreenButtonText, action: onStart)
                    .padding(.top, 20)
            }
        }

        private var foregroundTextColor: Color {
            appearance.textColor ?? appearance.backgroundColor.getContrastingTextColor()
        }
    }

    @available(iOS 15.0, *)
    #Preview {
        IntroMessage {}
    }
#endif
