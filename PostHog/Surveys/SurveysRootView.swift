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
                    SurveySheet(
                        survey: survey,
                        isSurveyCompleted: displayManager.isSurveyCompleted,
                        currentQuestionIndex: displayManager.currentQuestionIndex,
                        onClose: displayManager.dismissSurvey,
                        onNextQuestionClicked: displayManager.onNextQuestion
                    )
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
