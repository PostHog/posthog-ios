//
//  SurveyDisplayController.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS) || Testing
    import SwiftUI

    final class SurveyDisplayController: ObservableObject {
        @Published var displayedSurvey: PostHogDisplaySurvey?
        @Published var isSurveyCompleted: Bool = false
        @Published var currentQuestionIndex: Int = 0

        var onSurveyShown: OnPostHogSurveyShown?
        var onSurveyResponse: OnPostHogSurveyResponse?
        var onSurveyClosed: OnPostHogSurveyClosed?

        func showSurvey(_ survey: PostHogDisplaySurvey) {
            guard displayedSurvey == nil else {
                hedgeLog("[Surveys] Already displaying a survey. Skipping")
                return
            }

            displayedSurvey = survey
            isSurveyCompleted = false
            currentQuestionIndex = 0
            onSurveyShown?(survey)
        }

        /// Replaces the content of the survey currently on screen (e.g. with a new translation)
        /// without resetting the current question, completion state, or any in-progress answers.
        ///
        /// No-op if no survey is displayed or the update targets a different survey.
        func updateSurvey(_ survey: PostHogDisplaySurvey) {
            guard let displayedSurvey, displayedSurvey.id == survey.id else {
                hedgeLog("[Surveys] Received an update for a non-displayed survey. Skipping")
                return
            }

            self.displayedSurvey = survey
        }

        func onNextQuestion(index: Int, response: PostHogSurveyResponse) {
            guard let displayedSurvey else { return }
            guard let next = onSurveyResponse?(displayedSurvey, index, response) else { return }

            currentQuestionIndex = next.questionIndex
            isSurveyCompleted = next.isSurveyCompleted

            // auto-dismiss survey when completed
            if isSurveyCompleted, displayedSurvey.appearance?.displayThankYouMessage == false {
                dismissSurvey()
            }
        }

        // User dismissed survey
        func dismissSurvey() {
            if let survey = displayedSurvey {
                onSurveyClosed?(survey)
            }
            displayedSurvey = nil
            isSurveyCompleted = false
            currentQuestionIndex = 0
        }
    }

#endif
