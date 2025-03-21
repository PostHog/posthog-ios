//
//  SurveysRootView.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS)
    import SwiftUI

    struct SurveysRootView: View {
        @EnvironmentObject private var displayManager: SurveysDisplayController

        var body: some View {
            Color.clear
                .allowsHitTesting(false)
                .sheet(item: displayBinding) { survey in
                    Color.clear
                        .overlay(
                            VStack {
                                Text("Displaying \(survey)")

                                Button("Survey Sent") {
                                    displayManager.completeSurvey()
                                }

                                Button("Survey Dismissed") {
                                    displayManager.userDismissedSurvey()
                                }
                            }
                        )
                        .frame(height: 300)
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
