//
//  BottomSection.swift
//  PostHog
//
//  Created by Ioannis Josephides on 18/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct BottomSection: View {
        let label: String
        let action: () -> Void

        var body: some View {
            Button(label, action: action)
                .buttonStyle(SurveyButtonStyle())
                .padding(.bottom, 16)
        }
    }

#endif
