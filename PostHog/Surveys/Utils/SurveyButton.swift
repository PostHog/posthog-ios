//
//  SuveyButton.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)

    import SwiftUI

    struct SurveyButton: View {
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(label)
                    .foregroundColor(.white)
            }
            .buttonStyle(SurveyButtonStyle())
        }
    }

    private struct SurveyButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .shadow(color: Color.black.opacity(0.12), radius: 0, x: 0, y: -1) // Text shadow
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 2)// Box shadow
                )
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.80 : opacity)
        }
        
        private var opacity: Double {
            isEnabled ? 1.0 : 0.5
        }
    }

    #Preview {
        SurveyButton(label: "Submit") {
            //
        }
        .padding()
        .disabled(false)
    }

#endif
