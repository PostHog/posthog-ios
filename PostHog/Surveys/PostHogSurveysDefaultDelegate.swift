//
//  PostHogSurveysDefaultDelegate.swift
//  PostHog
//
//  Created by Ioannis Josephides on 18/06/2025.
//

#if os(iOS)
    import UIKit
#else
    import Foundation
#endif

final class PostHogSurveysDefaultDelegate: PostHogSurveysDelegate {
    #if os(iOS)
        private var surveysWindow: UIWindow?
        private var displayController: SurveyDisplayController?
    #endif

    func renderSurvey(
        _ survey: PostHogDisplaySurvey,
        onSurveyShown: @escaping OnPostHogSurveyShown,
        onSurveyResponse: @escaping OnPostHogSurveyResponse,
        onSurveyClosed: @escaping OnPostHogSurveyClosed
    ) {
        #if os(iOS)
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
        #endif
    }

    func cleanupSurveys() {
        #if os(iOS)
            displayController?.dismissSurvey() // dismiss any active surveys
            surveysWindow?.rootViewController?.dismiss(animated: true) {
                self.surveysWindow?.isHidden = true
                self.surveysWindow = nil
                self.displayController = nil
            }
        #endif
    }

    #if os(iOS)
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
    #endif
}
