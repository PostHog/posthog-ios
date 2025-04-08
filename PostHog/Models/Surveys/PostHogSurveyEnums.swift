//
//  PostHogSurveyEnums.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

// MARK: - Supporting Types

enum PostHogSurveyType: String, Decodable {
    case popover, api, widget
}

enum PostHogSurveyQuestionType: String, Decodable {
    case open
    case link
    case rating
    case multipleChoice = "multiple_choice"
    case singleChoice = "single_choice"
}

enum PostHogSurveyTextContentType: String, Decodable {
    case html, text
}

enum PostHogSurveyMatchType: String, Decodable {
    case regex
    case notRegex = "not_regex"
    case exact
    case isNot = "is_not"
    case iContains = "icontains"
    case notIContains = "not_icontains"
}

enum PostHogSurveyAppearancePosition: String, Decodable {
    case left, right, center
}

enum PostHogSurveyAppearanceWidgetType: String, Decodable {
    case button, tab, selector
}

enum PostHogSurveyRatingDisplayType: String, Decodable {
    case number, emoji
}

enum PostHogSurveyQuestionBranchingType: String, Decodable {
    case nextQuestion = "next_question"
    case end
    case responseBased = "response_based"
    case specificQuestion = "specific_question"
}

enum PostHogSurveyResponse {
    case link(String)
    case rating(Int?)
    case openEnded(String?)
    case singleChoice(String?)
    case multipleChoice([String]?)
}
