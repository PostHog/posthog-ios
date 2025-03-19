//
//  SurveyDisplayController.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS)
    import SwiftUI

    final class SurveyDisplayController: ObservableObject {
        @Published var displayedSurvey: Survey?
        @Published var isSurveySent: Bool = false
        @Published var currentQuestionIndex: Int?

        typealias NextStepHandler = (_ survey: Survey, _ currentQuestionIndex: Int) -> Int
        typealias GetSurveyCompletedHandler = (_ survey: Survey, _ currentQuestionIndex: Int) -> Bool
        typealias SurveyCompletedHandler = (_ survey: Survey) -> Void
        typealias SurveyDismissedHandler = (_ survey: Survey) -> Void

        let getNextSurveyStep: NextStepHandler
        let getSurveyCompleted: GetSurveyCompletedHandler
        let onSurveyCompleted: SurveyCompletedHandler
        let onSurveyDismissed: SurveyDismissedHandler

        init(
            getNextSurveyStep: @escaping NextStepHandler,
            getSurveyCompleted: @escaping GetSurveyCompletedHandler,
            onSurveyCompleted: @escaping SurveyCompletedHandler,
            onSurveyDismissed: @escaping SurveyDismissedHandler
        ) {
            self.getNextSurveyStep = getNextSurveyStep
            self.getSurveyCompleted = getSurveyCompleted
            self.onSurveyCompleted = onSurveyCompleted
            self.onSurveyDismissed = onSurveyDismissed
        }

        func showSurvey(_ survey: Survey) {
            guard displayedSurvey == nil else {
                hedgeLog("Already displaying a survey. Skipping")
                return
            }

            displayedSurvey = survey
            isSurveySent = false
            currentQuestionIndex = 0
        }

        // User swiped down to dismiss survey
        func hideSurvey() {
            displayedSurvey = nil
            isSurveySent = false
            currentQuestionIndex = nil
        }

        func onNextQuestion() {
            guard let displayedSurvey, let currentQuestionIndex else { return }
            self.currentQuestionIndex = getNextSurveyStep(displayedSurvey, currentQuestionIndex)

            if getSurveyCompleted(displayedSurvey, currentQuestionIndex) {
                onSurveyCompleted(displayedSurvey)
                isSurveySent = true
            }
        }

        // User explicitly dismissed survey
        func userDismissedSurvey() {
            guard let survey = displayedSurvey else { return }
            if !isSurveySent {
                onSurveyDismissed(survey)
            }
            displayedSurvey = nil
            isSurveySent = false
        }

        func canShow(_: Survey) -> Bool {
            true
        }
    }
#endif
