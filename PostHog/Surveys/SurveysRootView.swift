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
                        isSurveySent: displayManager.isSurveySent ?? false,
                        currentQuestionIndex: displayManager.currentQuestionIndex,
                        onClose: displayManager.userDismissedSurvey,
                        onNextQuestionClicked: { _, _ in
                            // TODO: handle response
                            displayManager.onNextQuestion()
                        }
                    )
                }
        }

        private var displayBinding: Binding<Survey?> {
            .init(
                get: {
                    displayManager.displayedSurvey
                },
                set: { newValue in
                    if newValue == nil {
                        displayManager.hideSurvey()
                    }
                }
            )
        }
    }
#endif
