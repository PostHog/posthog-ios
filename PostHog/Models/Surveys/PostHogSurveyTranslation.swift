//
//  PostHogSurveyTranslation.swift
//  PostHog
//
//  Created by PostHog Code on 2026-05-13.
//

import Foundation

/// Localized overrides for a survey's user-visible strings.
///
/// Attached to `PostHogSurvey.translations` as a map keyed by language code
/// (e.g. `"fr"`, `"pt-BR"`). All fields are optional — missing fields fall back to the
/// original survey value.
///
/// Note: the survey-level `description` is intentionally NOT translatable. It is only
/// used for internal previews and never rendered to end users.
struct PostHogSurveyTranslation: Decodable {
    let name: String?
    let thankYouMessageHeader: String?
    let thankYouMessageDescription: String?
    let thankYouMessageCloseButtonText: String?
}

/// Localized overrides for a survey question's user-visible strings.
///
/// Attached to each `PostHogSurveyQuestion`-conforming struct as a map keyed by
/// language code. All fields are optional. Fields irrelevant to a given question type
/// (e.g. `choices` on a rating question) are ignored.
struct PostHogSurveyQuestionTranslation: Decodable {
    let question: String?
    let description: String?
    let buttonText: String?
    let link: String?
    let lowerBoundLabel: String?
    let upperBoundLabel: String?
    let choices: [String]?
}
