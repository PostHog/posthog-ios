//
//  PostHogSurveysConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/04/2025.
//

#if os(iOS)
    import Foundation

    public typealias OnPostHogSurveyShown = (_ survey: PostHogDisplaySurvey) -> Void
    public typealias OnPostHogSurveyResponse = (_ survey: PostHogDisplaySurvey, _ index: Int, _ response: PostHogSurveyResponse) -> PostHogNextSurveyQuestion?
    public typealias OnPostHogSurveyClosed = (_ survey: PostHogDisplaySurvey) -> Void

    @objc public class PostHogSurveysConfig: NSObject {
        public var surveysDelegate: PostHogSurveysDelegate = PostHogSurveysDisplayDelegate()
    }

    @objc public protocol PostHogSurveysDelegate {
        /// Called when an activated PostHog survey needs to be rendered on the app's UI
        ///
        /// - Parameters:
        ///   - survey: The survey to be displayed to the user
        ///   - onSurveyShown: Call this when the survey is successfully displayed
        ///   - onSurveyResponse: To be called the user submits a response to a question.
        ///     - This callback returns the next question index and a flag indicating wether the survey has reached its end
        ///     - Open questions: String
        ///     - Rating questions: Int
        ///     - Multiple/Single choice: String
        ///     - Link questions: "link clicked" if the application handled the link, nil otherwise
        ///   - onSurveyClosed: To be called when the survey is dismissed
        @objc func renderSurvey(
            _ survey: PostHogDisplaySurvey,
            onSurveyShown: @escaping OnPostHogSurveyShown,
            onSurveyResponse: @escaping OnPostHogSurveyResponse,
            onSurveyClosed: @escaping OnPostHogSurveyClosed
        )

        /// Called when surveys are stopped to clean up any UI elements and reset the survey display state.
        /// This method should handle the dismissal of any active surveys and cleanup of associated resources.
        @objc func surveysStopped()
    }
#endif
