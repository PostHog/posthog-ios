//
//  PostHogDisplaySurvey.swift
//  PostHog
//
//  Created by Ioannis Josephides on 18/06/2025.
//

import Foundation

/// A model representing a PostHog survey to be displayed to users
@objc public class PostHogDisplaySurvey: NSObject, Identifiable {
    /// Unique identifier for the survey
    public let id: String
    /// Name of the survey
    public let name: String
    /// Array of questions to be presented in the survey
    public let questions: [PostHogDisplaySurveyQuestion]
    /// Optional appearance configuration for customizing the survey's look and feel
    public let appearance: PostHogDisplaySurveyAppearance?
    /// Optional date indicating when the survey should start being shown
    public let startDate: Date?
    /// Optional date indicating when the survey should stop being shown
    public let endDate: Date?

    init(
        id: String,
        name: String,
        questions: [PostHogDisplaySurveyQuestion],
        appearance: PostHogDisplaySurveyAppearance?,
        startDate: Date?,
        endDate: Date?
    ) {
        self.id = id
        self.name = name
        self.questions = questions
        self.appearance = appearance
        self.startDate = startDate
        self.endDate = endDate
        super.init()
    }
}

/// Type of rating display for survey rating questions
@objc public enum PostHogDisplaySurveyRatingType: Int {
    /// Display numeric rating options
    case number
    /// Display emoji rating options
    case emoji
}

/// Content type for text-based survey elements
@objc public enum PostHogDisplaySurveyTextContentType: Int {
    /// Content should be rendered as HTML
    case html
    /// Content should be rendered as plain text
    case text
}
