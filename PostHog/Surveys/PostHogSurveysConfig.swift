//
//  PostHogSurveysConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/04/2025.
//

import Foundation

/// Configuration for mobile survey rendering.
///
/// Mutate fields on `PostHogConfig.surveysConfig` before SDK setup to customize survey UI,
/// lifecycle handling, or localization.
@objc public class PostHogSurveysConfig: NSObject {
    /// Delegate responsible for managing survey presentation in your app.
    /// Handles survey rendering, response collection, and lifecycle events.
    /// You can provide your own delegate for a custom survey presentation.
    ///
    /// Defaults to `PostHogSurveysDefaultDelegate` which provides a standard survey UI.
    public var surveysDelegate: PostHogSurveysDelegate = PostHogSurveysDefaultDelegate()

    /// Optional explicit override for the language used when rendering surveys.
    ///
    /// When set, surveys with matching entries in `translations` will be rendered in
    /// this language regardless of the device locale or any `language` person property.
    ///
    /// Format: a language tag such as `"fr"`, `"pt-BR"`, `"zh-CN"`. Matching is
    /// case-insensitive and falls back to the base language (e.g. `"pt"` if `"pt-BR"`
    /// is requested but only `"pt"` is provided).
    ///
    /// Blank or `nil` values are treated as unset.
    ///
    /// Default: `nil`.
    @objc public var overrideDisplayLanguage: String?
}

/// To be called when a survey is successfully shown to the user
/// - Parameter survey: The survey that was displayed
public typealias OnPostHogSurveyShown = (_ survey: PostHogDisplaySurvey) -> Void

/// To be called when a user responds to a survey question
/// - Parameters:
///   - survey: The current survey being displayed
///   - index: The index of the question being answered
///   - response: The user's response to the question
/// - Returns: The next survey state, or `nil` to leave the displayed survey state unchanged.
public typealias OnPostHogSurveyResponse = (_ survey: PostHogDisplaySurvey, _ index: Int, _ response: PostHogSurveyResponse) -> PostHogNextSurveyQuestion?

/// To be called when a survey is dismissed
/// - Parameter survey: The survey that was closed
public typealias OnPostHogSurveyClosed = (_ survey: PostHogDisplaySurvey) -> Void

/// Delegate used by the SDK to present surveys and receive survey lifecycle callbacks.
@objc public protocol PostHogSurveysDelegate {
    /// Called when an activated PostHog survey needs to be rendered on the app's UI
    ///
    /// - Parameters:
    ///   - survey: The survey to be displayed to the user
    ///   - onSurveyShown: To be called when the survey is successfully displayed to the user.
    ///   - onSurveyResponse: Call when the user submits a response to a question; use the returned state to advance or complete the survey.
    ///   - onSurveyClosed: To be called when the survey is dismissed
    @objc func renderSurvey(
        _ survey: PostHogDisplaySurvey,
        onSurveyShown: @escaping OnPostHogSurveyShown,
        onSurveyResponse: @escaping OnPostHogSurveyResponse,
        onSurveyClosed: @escaping OnPostHogSurveyClosed
    )

    /// Called when the content of the currently displayed survey changes without restarting it,
    /// for example when the user's language is updated and a new translation becomes available.
    ///
    /// Implementations should update the on-screen survey in place — preserving the current
    /// question, progress, and any in-progress answers — rather than presenting it again.
    /// Optional: delegates that don't support live updates can omit it and the survey simply
    /// keeps the language it was first rendered with.
    ///
    /// Always delivered on the main thread. May arrive *before* the survey is visibly shown —
    /// e.g. while a display delay (`surveyPopupDelaySeconds`) is still pending — so a delegate
    /// that defers presentation must also apply the update to its pending survey, otherwise the
    /// update is dropped and the survey shows the language it was first resolved with.
    ///
    /// - Parameter survey: The survey with refreshed (e.g. re-translated) content. Its `id`
    ///   matches the survey passed to `renderSurvey`.
    @objc optional func updateSurvey(_ survey: PostHogDisplaySurvey)

    /// Called when surveys are stopped to clean up any UI elements and reset the survey display state.
    /// This method should handle the dismissal of any active surveys and cleanup of associated resources.
    @objc func cleanupSurveys()
}
