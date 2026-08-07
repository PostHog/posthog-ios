//
//  PostHogDisplaySurveyAppearance.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/06/2025.
//

import Foundation

/// Model that describes the appearance customization of a PostHog survey
@objc public class PostHogDisplaySurveyAppearance: NSObject {
    // General
    /// Optional font family to use throughout the survey
    public let fontFamily: String?
    /// Optional background color as web color (e.g. "#FFFFFF" or "white")
    public let backgroundColor: String?
    /// Optional border color as web color
    public let borderColor: String?

    // Submit button
    /// Optional background color for the submit button as web color
    public let submitButtonColor: String?
    /// Optional custom text for the submit button
    public let submitButtonText: String?
    /// Optional text color for the submit button as web color
    public let submitButtonTextColor: String?

    // Text colors
    /// Optional primary text color as web color (for questions, close button, etc.)
    public let textColor: String?
    /// Optional color for description text as web color
    public let descriptionTextColor: String?

    // Rating buttons
    /// Optional color for rating buttons as web color
    public let ratingButtonColor: String?
    /// Optional color for active/selected rating buttons as web color
    public let ratingButtonActiveColor: String?

    // Input
    /// Optional background color for input fields as web color
    public let inputBackground: String?
    /// Optional text color for input fields as web color
    public let inputTextColor: String?
    /// Optional placeholder text for input fields
    public let placeholder: String?

    // Display
    /// Optional delay in seconds before showing the survey
    public let surveyPopupDelaySeconds: TimeInterval?

    // Thank you message
    /// Whether to show a thank you message after survey completion
    public let displayThankYouMessage: Bool
    /// Optional header text for the thank you message
    public let thankYouMessageHeader: String?
    /// Optional description text for the thank you message
    public let thankYouMessageDescription: String?
    /// Optional content type for the thank you message description
    public let thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType?
    /// Optional text for the close button in the thank you message
    public let thankYouMessageCloseButtonText: String?

    // Intro screen
    /// Whether to show an intro screen before the first question
    public let displayIntroScreen: Bool
    /// Optional header text for the intro screen
    public let introScreenHeader: String?
    /// Optional description text for the intro screen
    public let introScreenDescription: String?
    /// Optional content type for the intro screen description
    public let introScreenDescriptionContentType: PostHogDisplaySurveyTextContentType?
    /// Optional text for the button that advances past the intro screen
    public let introScreenButtonText: String?

    init(
        fontFamily: String?,
        backgroundColor: String?,
        borderColor: String?,
        submitButtonColor: String?,
        submitButtonText: String?,
        submitButtonTextColor: String?,
        textColor: String?,
        descriptionTextColor: String?,
        ratingButtonColor: String?,
        ratingButtonActiveColor: String?,
        inputBackground: String?,
        inputTextColor: String?,
        placeholder: String?,
        surveyPopupDelaySeconds: TimeInterval?,
        displayThankYouMessage: Bool,
        thankYouMessageHeader: String?,
        thankYouMessageDescription: String?,
        thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType?,
        thankYouMessageCloseButtonText: String?,
        displayIntroScreen: Bool = false,
        introScreenHeader: String? = nil,
        introScreenDescription: String? = nil,
        introScreenDescriptionContentType: PostHogDisplaySurveyTextContentType? = nil,
        introScreenButtonText: String? = nil
    ) {
        self.fontFamily = fontFamily
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.submitButtonColor = submitButtonColor
        self.submitButtonText = submitButtonText
        self.submitButtonTextColor = submitButtonTextColor
        self.textColor = textColor
        self.descriptionTextColor = descriptionTextColor
        self.ratingButtonColor = ratingButtonColor
        self.ratingButtonActiveColor = ratingButtonActiveColor
        self.inputBackground = inputBackground
        self.inputTextColor = inputTextColor
        self.placeholder = placeholder
        self.surveyPopupDelaySeconds = surveyPopupDelaySeconds
        self.displayThankYouMessage = displayThankYouMessage
        self.thankYouMessageHeader = thankYouMessageHeader
        self.thankYouMessageDescription = thankYouMessageDescription
        self.thankYouMessageDescriptionContentType = thankYouMessageDescriptionContentType
        self.thankYouMessageCloseButtonText = thankYouMessageCloseButtonText
        self.displayIntroScreen = displayIntroScreen
        self.introScreenHeader = introScreenHeader
        self.introScreenDescription = introScreenDescription
        self.introScreenDescriptionContentType = introScreenDescriptionContentType
        self.introScreenButtonText = introScreenButtonText
        super.init()
    }
}
