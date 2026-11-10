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
                        .allowsHitTesting(false)
                    PositionedSurveyCard(displayManager: displayManager, fallbackSurvey: survey)
                        .frame(maxWidth: 420)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placementAlignment)
                }
            }
        }

        private var placement: SurveyPlacement {
            SurveyPlacement.resolve(wire: displayManager.displayedSurvey?.appearance?.position)
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

        /// The card lives in its own hosting controller. `SurveysWindow` is a passthrough
        /// window and drops any hit that resolves to the root hosting view, which is what
        /// a SwiftUI button drawn directly in that root does. A separate view keeps the
        /// close button, and the rest of the card, in the hit-test chain.
        private struct PositionedSurveyCard: UIViewControllerRepresentable {
            @ObservedObject var displayManager: SurveyDisplayController
            let fallbackSurvey: PostHogDisplaySurvey

            func makeUIViewController(context _: Context) -> UIHostingController<AnyView> {
                let controller = UIHostingController(rootView: card)
                controller.view.backgroundColor = .clear
                if #available(iOS 16.0, *) {
                    controller.sizingOptions = .intrinsicContentSize
                }
                return controller
            }

            func updateUIViewController(_ controller: UIHostingController<AnyView>, context _: Context) {
                controller.rootView = card
            }

            private var card: AnyView {
                AnyView(
                    SurveySheet(displayManager: displayManager, fallbackSurvey: fallbackSurvey, presentsAsSheet: false)
                        .environment(\.colorScheme, .light)
                )
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
