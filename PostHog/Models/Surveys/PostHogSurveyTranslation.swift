//
//  PostHogSurveyTranslation.swift
//  PostHog
//
//  Created by PostHog Code on 2026-05-13.
//

import Foundation

/// Localized overrides for a survey, keyed by language code (e.g. `"fr"`, `"pt-BR"`).
///
/// The survey-level `description` is intentionally NOT translatable — it is only used
/// for internal previews and never rendered to end users.
struct PostHogSurveyTranslation: Decodable {
    let name: String?
    let thankYouMessageHeader: String?
    let thankYouMessageDescription: String?
    let thankYouMessageCloseButtonText: String?
}

/// Localized overrides for a survey question.
///
/// Fields are a superset across question types: `link` only applies to link questions,
/// `lowerBoundLabel` / `upperBoundLabel` only to rating questions, and `choices` only
/// to single/multiple choice questions. Irrelevant fields are ignored for other types.
struct PostHogSurveyQuestionTranslation: Decodable {
    let question: String?
    let description: String?
    let buttonText: String?
    let link: String?
    let lowerBoundLabel: String?
    let upperBoundLabel: String?
    let choices: [String]?
}
