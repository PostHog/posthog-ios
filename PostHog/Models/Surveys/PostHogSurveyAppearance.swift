//
//  PostHogSurveyAppearance.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

/// Represents the appearance settings for the survey, such as colors, fonts, and layout
struct PostHogSurveyAppearance: Decodable {
    public let position: PostHogSurveyAppearancePosition?
    public let fontFamily: String?
    public let backgroundColor: String?
    public let submitButtonColor: String?
    public let submitButtonText: String?
    public let submitButtonTextColor: String?
    public let descriptionTextColor: String?
    public let ratingButtonColor: String?
    public let ratingButtonActiveColor: String?
    public let ratingButtonHoverColor: String?
    public let whiteLabel: Bool?
    public let autoDisappear: Bool?
    public let displayThankYouMessage: Bool?
    public let thankYouMessageHeader: String?
    public let thankYouMessageDescription: String?
    public let thankYouMessageDescriptionContentType: PostHogSurveyTextContentType?
    public let thankYouMessageCloseButtonText: String?
    public let borderColor: String?
    public let placeholder: String?
    public let shuffleQuestions: Bool?
    public let surveyPopupDelaySeconds: TimeInterval?
    // widget options
    public let widgetType: PostHogSurveyAppearanceWidgetType?
    public let widgetSelector: String?
    public let widgetLabel: String?
    public let widgetColor: String?
}
