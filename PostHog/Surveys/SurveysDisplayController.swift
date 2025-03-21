//
//  SurveysDisplayController.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS)
    import SwiftUI

    final class SurveysDisplayController: ObservableObject {
        @Published var displayedSurvey: Survey?

        typealias NextStepHandler = (_ survey: Survey, _ currentQuestionIndex: Int, _ response: SurveyResponse) -> Int
        typealias SurveySentHandler = (_ survey: Survey) -> Void
        typealias SurveyDismissedHandler = (_ survey: Survey) -> Void

        let getNextSurveyStep: NextStepHandler
        let onSurveySent: SurveySentHandler
        let onSurveyDismissed: SurveyDismissedHandler

        init(
            getNextSurveyStep: @escaping NextStepHandler,
            onSurveySent: @escaping SurveySentHandler,
            onSurveyDismissed: @escaping SurveyDismissedHandler
        ) {
            self.getNextSurveyStep = getNextSurveyStep
            self.onSurveySent = onSurveySent
            self.onSurveyDismissed = onSurveyDismissed
        }

        func showSurvey(_ survey: Survey) {
            displayedSurvey = survey
        }

        // User swiped down to dismiss survey
        func hideSurvey() {}

        // User explicitly dismissed survey
        func userDismissedSurvey() {
            guard let survey = displayedSurvey else { return }
            onSurveyDismissed(survey)
        }

        // User has completed survey
        func completeSurvey() {
            guard let survey = displayedSurvey else { return }
            onSurveySent(survey)
        }

        func canShow(_: Survey) -> Bool {
            true
        }
    }
#endif
