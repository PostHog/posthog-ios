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
