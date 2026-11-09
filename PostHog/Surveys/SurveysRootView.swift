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
            if placement.usesBottomSheet {
                Color.clear
                    .allowsHitTesting(false)
                    .sheet(item: displayBinding) { survey in
                        // Content is driven by the display controller so in-place updates (like a
                        // survey being re-translated after a language change) render live; the
                        // `.sheet(item:)` snapshot is the fallback that keeps content on screen
                        // during the dismiss animation, after `displayedSurvey` is cleared.
                        SurveySheet(displayManager: displayManager, fallbackSurvey: survey, presentsAsSheet: true)
                            .environment(\.colorScheme, .light) // enforce light theme for now
                    }
            } else if let survey = displayManager.displayedSurvey {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    positionedSurvey(survey)
                }
            }
        }

        private var placement: SurveyPlacement {
            SurveyPlacement.resolve(wire: displayManager.displayedSurvey?.appearance?.position)
        }

        private func positionedSurvey(_ survey: PostHogDisplaySurvey) -> some View {
            SurveySheet(displayManager: displayManager, fallbackSurvey: survey, presentsAsSheet: false)
                .environment(\.colorScheme, .light)
                .frame(maxWidth: 420)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placementAlignment)
        }

        private var placementAlignment: Alignment {
            let vertical: VerticalAlignment
            switch placement.vertical {
            case .top:
                vertical = .top
            case .middle:
                vertical = .center
            case .bottom:
                vertical = .bottom
            }

            let horizontal: HorizontalAlignment
            switch placement.horizontal {
            case .leading:
                horizontal = .leading
            case .center:
                horizontal = .center
            case .trailing:
                horizontal = .trailing
            }

            return Alignment(horizontal: horizontal, vertical: vertical)
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
