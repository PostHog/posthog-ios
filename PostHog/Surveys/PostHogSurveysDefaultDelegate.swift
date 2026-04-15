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
        private var pendingDisplayWorkItem: DispatchWorkItem?
        private var pendingSurvey: PostHogDisplaySurvey?
        private var pendingSurveyClosedHandler: OnPostHogSurveyClosed?
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

            guard let displayController else {
                // If we cannot render the survey UI, treat this as a pre-render dismiss so integration state is cleared.
                onSurveyClosed(survey)
                return
            }

            // Setup handlers
            displayController.onSurveyShown = onSurveyShown
            displayController.onSurveyResponse = onSurveyResponse
            displayController.onSurveyClosed = onSurveyClosed

            scheduleSurveyDisplay(survey, displayController: displayController, onSurveyClosed: onSurveyClosed)
        #endif
    }

    func cleanupSurveys() {
        #if os(iOS)
            dismissPendingSurveyIfNeeded()
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

        private func scheduleSurveyDisplay(
            _ survey: PostHogDisplaySurvey,
            displayController: SurveyDisplayController,
            onSurveyClosed: @escaping OnPostHogSurveyClosed
        ) {
            dismissPendingSurveyIfNeeded()

            let delay = max(survey.appearance?.surveyPopupDelaySeconds ?? 0, 0)
            guard delay > 0 else {
                // show the survey directly
                displayController.showSurvey(survey)
                return
            }

            hedgeLog("[Surveys] Scheduling survey \(survey.id) display in \(delay) seconds")

            // schedule a survey display for now + delay
            pendingSurvey = survey
            pendingSurveyClosedHandler = onSurveyClosed

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.pendingSurvey?.id == survey.id else {
                    // current survey?
                    return
                }

                self.pendingDisplayWorkItem = nil
                self.pendingSurvey = nil
                self.pendingSurveyClosedHandler = nil
                displayController.showSurvey(survey)
            }

            pendingDisplayWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func dismissPendingSurveyIfNeeded() {
            guard let pendingSurvey else { return }

            pendingDisplayWorkItem?.cancel()
            pendingDisplayWorkItem = nil
            self.pendingSurvey = nil

            let pendingClosedHandler = pendingSurveyClosedHandler
            pendingSurveyClosedHandler = nil
            pendingClosedHandler?(pendingSurvey)
        }
    #endif
}
