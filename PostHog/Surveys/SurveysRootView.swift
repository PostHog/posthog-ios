//
//  SurveysRootView.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct SurveysRootView: View {
        @EnvironmentObject private var displayManager: SurveyDisplayController

        var body: some View {
            Color.clear
                .allowsHitTesting(false)
                .sheet(item: displayBinding) { _ in
                    // Drive the sheet content from the display controller (not the snapshot
                    // passed by `.sheet(item:)`) so in-place updates — like a survey being
                    // re-translated after a language change — are reflected live.
                    SurveySheet(displayManager: displayManager)
                        .environment(\.colorScheme, .light) // enforce light theme for now
                }
        }

        private var displayBinding: Binding<PostHogDisplaySurvey?> {
            .init(
                get: {
                    displayManager.displayedSurvey
                },
                set: { newValue in
                    // in case interactive dismiss is allowed
                    if newValue == nil {
                        displayManager.dismissSurvey()
                    }
                }
            )
        }
    }
#endif
