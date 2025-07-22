//
//  PostHogSurveyAppearance.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

/// Represents the appearance settings for the survey, such as colors, fonts, and layout
struct PostHogSurveyAppearance: Decodable {
    let position: PostHogSurveyAppearancePosition?
    let fontFamily: String?
    let backgroundColor: String?
    let submitButtonColor: String?
    let submitButtonText: String?
    let submitButtonTextColor: String?
    let descriptionTextColor: String?
    let ratingButtonColor: String?
    let ratingButtonActiveColor: String?
    let ratingButtonHoverColor: String?
    let whiteLabel: Bool?
    let autoDisappear: Bool?
    let displayThankYouMessage: Bool?
    let thankYouMessageHeader: String?
    let thankYouMessageDescription: String?
    let thankYouMessageDescriptionContentType: PostHogSurveyTextContentType?
    let thankYouMessageCloseButtonText: String?
    let borderColor: String?
    let placeholder: String?
    let shuffleQuestions: Bool?
    let surveyPopupDelaySeconds: TimeInterval?
    // widget options
    let widgetType: PostHogSurveyAppearanceWidgetType?
    let widgetSelector: String?
    let widgetLabel: String?
    let widgetColor: String?
}
