//
//  PostHogSurveyConditions.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

/// Represents conditions for displaying the survey, such as URL or event-based triggers
struct PostHogSurveyConditions: Decodable {
    /// Target URL for the survey (optional)
    let url: String?
    /// The match type for the url condition (optional)
    let urlMatchType: PostHogSurveyMatchType?
    /// CSS selector for displaying the survey (optional)
    let selector: String?
    /// Device type based conditions for displaying the survey (optional)
    let deviceTypes: [String]?
    /// The match type for the device type condition (optional)
    let deviceTypesMatchType: PostHogSurveyMatchType?
    /// Minimum wait period before showing the survey again (optional)
    let seenSurveyWaitPeriodInDays: Int?
    /// Event-based conditions for displaying the survey (optional)
    let events: PostHogSurveyEventConditions?
    /// Action-based conditions for displaying the survey (optional)
    let actions: PostHogSurveyActionsConditions?
}

/// Represents event-based conditions for displaying the survey
struct PostHogSurveyEventConditions: Decodable {
    let repeatedActivation: Bool?
    /// List of events that trigger the survey
    let values: [PostHogEventCondition]
}

/// Represents action-based conditions for displaying the survey
struct PostHogSurveyActionsConditions: Decodable {
    /// List of events that trigger the survey
    let values: [PostHogEventCondition]
}

/// Represents a single event condition used in survey targeting
struct PostHogEventCondition: Decodable, Equatable {
    /// Name of the event (e.g., "content loaded")
    let name: String
}
