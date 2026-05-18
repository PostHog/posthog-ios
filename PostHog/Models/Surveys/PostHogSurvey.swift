//
//  PostHogSurvey.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/01/2025.
//

import Foundation

/// Represents the main survey object containing metadata, questions, conditions, and appearance settings.
/// see: posthog-js/posthog-surveys-types.ts
struct PostHogSurvey: Decodable, Identifiable {
    /// The unique identifier for the survey
    let id: String
    /// The name of the survey
    let name: String
    /// Type of the survey (e.g., "popover")
    let type: PostHogSurveyType
    /// The questions asked in the survey
    let questions: [PostHogSurveyQuestion]
    /// Multiple feature flag keys. Must all (AND) evaluate to true for the survey to be shown (optional)
    let featureFlagKeys: [PostHogSurveyFeatureFlagKeyValue]?
    /// Linked feature flag key. Must evaluate to true for the survey to be shown (optional)
    let linkedFlagKey: String?
    /// Targeting feature flag key. Must evaluate to true for the survey to be shown (optional)
    let targetingFlagKey: String?
    /// Internal targeting flag key. Must evaluate to true for the survey to be shown (optional)
    let internalTargetingFlagKey: String?
    /// Conditions for displaying the survey (optional)
    let conditions: PostHogSurveyConditions?
    /// Appearance settings for the survey (optional)
    let appearance: PostHogSurveyAppearance?
    /// The iteration number for the survey (optional)
    let currentIteration: Int?
    /// The start date for the current iteration of the survey (optional)
    let currentIterationStartDate: Date?
    /// Start date of the survey (optional)
    let startDate: Date?
    /// End date of the survey (optional)
    let endDate: Date?
    /// The schedule for the survey (optional). Determines how often the survey can be shown.
    let schedule: PostHogSurveySchedule?
    let translations: [String: PostHogSurveyTranslation]?

    init(
        id: String,
        name: String,
        type: PostHogSurveyType,
        questions: [PostHogSurveyQuestion],
        featureFlagKeys: [PostHogSurveyFeatureFlagKeyValue]?,
        linkedFlagKey: String?,
        targetingFlagKey: String?,
        internalTargetingFlagKey: String?,
        conditions: PostHogSurveyConditions?,
        appearance: PostHogSurveyAppearance?,
        currentIteration: Int?,
        currentIterationStartDate: Date?,
        startDate: Date?,
        endDate: Date?,
        schedule: PostHogSurveySchedule?,
        translations: [String: PostHogSurveyTranslation]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.questions = questions
        self.featureFlagKeys = featureFlagKeys
        self.linkedFlagKey = linkedFlagKey
        self.targetingFlagKey = targetingFlagKey
        self.internalTargetingFlagKey = internalTargetingFlagKey
        self.conditions = conditions
        self.appearance = appearance
        self.currentIteration = currentIteration
        self.currentIterationStartDate = currentIterationStartDate
        self.startDate = startDate
        self.endDate = endDate
        self.schedule = schedule
        self.translations = translations
    }
}

struct PostHogSurveyFeatureFlagKeyValue: Equatable, Decodable {
    let key: String
    let value: String?
}
