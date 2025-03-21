//
//  SurveyDisplayController.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS)
    import SwiftUI

    final class SurveyDisplayController: ObservableObject {
        typealias NextStepHandler = (_ survey: Survey, _ currentQuestionIndex: Int) -> Int
        typealias GetSurveyCompletedHandler = (_ survey: Survey, _ currentQuestionIndex: Int) -> Bool
        typealias SurveyShownHandler = (_ survey: Survey) -> Void
        typealias SurveyResponseHandler = (_ survey: Survey, _ responses: [String: SurveyResponse], _ completed: Bool) -> Void
        typealias SurveyClosedHandler = (_ survey: Survey, _ completed: Bool) -> Void

        @Published var displayedSurvey: Survey?
        @Published var isSurveyCompleted: Bool = false
        @Published var currentQuestionIndex: Int?
        private var questionResponses: [String: SurveyResponse] = [:]

        private let getNextSurveyStep: NextStepHandler
        private let getSurveyCompleted: GetSurveyCompletedHandler
        private let onSurveyShown: SurveyShownHandler
        private let onSurveyResponse: SurveyResponseHandler
        private let onSurveyClosed: SurveyClosedHandler

        private let kSurveyResponseKey = "$survey_response"

        init(
            getNextSurveyStep: @escaping NextStepHandler,
            getSurveyCompleted: @escaping GetSurveyCompletedHandler,
            onSurveyShown: @escaping SurveyShownHandler,
            onSurveyResponse: @escaping SurveyResponseHandler,
            onSurveyClosed: @escaping SurveyClosedHandler
        ) {
            self.getNextSurveyStep = getNextSurveyStep
            self.getSurveyCompleted = getSurveyCompleted
            self.onSurveyShown = onSurveyShown
            self.onSurveyResponse = onSurveyResponse
            self.onSurveyClosed = onSurveyClosed
        }

        func showSurvey(_ survey: Survey) {
            guard displayedSurvey == nil else {
                hedgeLog("Already displaying a survey. Skipping")
                return
            }

            displayedSurvey = survey
            isSurveyCompleted = false
            currentQuestionIndex = 0
            onSurveyShown(survey)
        }

        // User swiped down to dismiss survey
        func hideSurvey() {
            displayedSurvey = nil
            isSurveyCompleted = false
            currentQuestionIndex = nil
            questionResponses = [:]
        }

        func onNextQuestion(index: Int, response: SurveyResponse) {
            guard let displayedSurvey else { return }
            let responseKey = index == 0 ? kSurveyResponseKey : "\(kSurveyResponseKey)_\(index)"
            questionResponses[responseKey] = response
            currentQuestionIndex = getNextSurveyStep(displayedSurvey, index)
            isSurveyCompleted = getSurveyCompleted(displayedSurvey, index)
            onSurveyResponse(displayedSurvey, questionResponses, isSurveyCompleted)
        }

        // User explicitly dismissed survey
        func userDismissedSurvey() {
            guard let survey = displayedSurvey else { return }
            onSurveyClosed(survey, isSurveyCompleted)
            displayedSurvey = nil
            isSurveyCompleted = false
        }

        func canShowNextSurvey() -> Bool {
            displayedSurvey == nil
        }
    }
#endif
