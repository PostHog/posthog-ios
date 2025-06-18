//
//  PostHogSurveysDisplayDelegate.swift
//  PostHog
//
//  Created by Ioannis Josephides on 18/06/2025.
//

#if os(iOS)
    import UIKit

    final class PostHogSurveysDisplayDelegate: PostHogSurveysDelegate {
        private var surveysWindow: UIWindow?
        private var displayController: SurveyDisplayController?

        func renderSurvey(
            _ survey: PostHogDisplaySurvey,
            onSurveyShown: @escaping OnPostHogSurveyShown,
            onSurveyResponse: @escaping OnPostHogSurveyResponse,
            onSurveyClosed: @escaping OnPostHogSurveyClosed
        ) {
            guard #available(iOS 15.0, *) else { return }

            if surveysWindow == nil {
                // setup window for first-time display
                setupWindow()
            }

            // Setup handlers
            displayController?.onSurveyShown = onSurveyShown
            displayController?.onSurveyResponse = onSurveyResponse
            displayController?.onSurveyClosed = onSurveyClosed

            // Display survey
            displayController?.showSurvey(survey)
        }

        func surveysStopped() {
            displayController?.dismissSurvey() // dismiss any active surveys
            surveysWindow?.rootViewController?.dismiss(animated: true) {
                self.surveysWindow?.isHidden = true
                self.surveysWindow = nil
                self.displayController = nil
            }
        }

        @available(iOS 15.0, *)
        private func setupWindow() {
            if let activeWindow = UIApplication.getCurrentWindow(), let activeScene = activeWindow.windowScene {
                let controller = SurveyDisplayController()
                displayController = controller
                surveysWindow = SurveysWindow(
                    controller: controller,
                    scene: activeScene
                )
                surveysWindow?.isHidden = false
                surveysWindow?.windowLevel = activeWindow.windowLevel + 1
            }
        }
    }
#endif
