//
//  PostHogSurveysConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/04/2025.
//

import Foundation

@objc public class PostHogSurveysConfig: NSObject {
    /// Delegate responsible for managing survey presentation in your app.
    /// Handles survey rendering, response collection, and lifecycle events.
    /// You can provide your own delegate for a custom survey presentation.
    ///
    /// Defaults to `PostHogSurveysDefaultDelegate` which provides a standard survey UI.
    public var surveysDelegate: PostHogSurveysDelegate = PostHogSurveysDefaultDelegate()
}

/// To be called when a survey is successfully shown to the user
/// - Parameter survey: The survey that was displayed
public typealias OnPostHogSurveyShown = (_ survey: PostHogDisplaySurvey) -> Void

/// To be called when a user responds to a survey question
/// - Parameters:
///   - survey: The current survey being displayed
///   - index: The index of the question being answered
///   - response: The user's response to the question
/// - Returns: The next question state (next question index and completion flag)
public typealias OnPostHogSurveyResponse = (_ survey: PostHogDisplaySurvey, _ index: Int, _ response: PostHogSurveyResponse) -> PostHogNextSurveyQuestion?

/// To be called when a survey is dismissed
/// - Parameter survey: The survey that was closed
public typealias OnPostHogSurveyClosed = (_ survey: PostHogDisplaySurvey) -> Void

@objc public protocol PostHogSurveysDelegate {
    /// Called when an activated PostHog survey needs to be rendered on the app's UI
    ///
    /// - Parameters:
    ///   - survey: The survey to be displayed to the user
    ///   - onSurveyShown: To be called when the survey is successfully displayed to the user.
    ///   - onSurveyResponse: To be called the user submits a response to a question.
    ///   - onSurveyClosed: To be called when the survey is dismissed
    @objc func renderSurvey(
        _ survey: PostHogDisplaySurvey,
        onSurveyShown: @escaping OnPostHogSurveyShown,
        onSurveyResponse: @escaping OnPostHogSurveyResponse,
        onSurveyClosed: @escaping OnPostHogSurveyClosed
    )

    /// Called when surveys are stopped to clean up any UI elements and reset the survey display state.
    /// This method should handle the dismissal of any active surveys and cleanup of associated resources.
    @objc func cleanupSurveys()
}
