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
                .sheet(item: displayBinding) { survey in
                    // Content is driven by the display controller so in-place updates (like a
                    // survey being re-translated after a language change) render live; the
                    // `.sheet(item:)` snapshot is the fallback that keeps content on screen
                    // during the dismiss animation, after `displayedSurvey` is cleared.
                    SurveySheet(displayManager: displayManager, fallbackSurvey: survey)
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
