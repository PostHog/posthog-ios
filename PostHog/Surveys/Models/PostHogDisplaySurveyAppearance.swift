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
    /// Optional color for description text as web color
    public let descriptionTextColor: String?

    // Rating buttons
    /// Optional color for rating buttons as web color
    public let ratingButtonColor: String?
    /// Optional color for active/selected rating buttons as web color
    public let ratingButtonActiveColor: String?

    // Input
    /// Optional placeholder text for input fields
    public let placeholder: String?

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

    init(
        fontFamily: String?,
        backgroundColor: String?,
        borderColor: String?,
        submitButtonColor: String?,
        submitButtonText: String?,
        submitButtonTextColor: String?,
        descriptionTextColor: String?,
        ratingButtonColor: String?,
        ratingButtonActiveColor: String?,
        placeholder: String?,
        displayThankYouMessage: Bool,
        thankYouMessageHeader: String?,
        thankYouMessageDescription: String?,
        thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType?,
        thankYouMessageCloseButtonText: String?
    ) {
        self.fontFamily = fontFamily
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.submitButtonColor = submitButtonColor
        self.submitButtonText = submitButtonText
        self.submitButtonTextColor = submitButtonTextColor
        self.descriptionTextColor = descriptionTextColor
        self.ratingButtonColor = ratingButtonColor
        self.ratingButtonActiveColor = ratingButtonActiveColor
        self.placeholder = placeholder
        self.displayThankYouMessage = displayThankYouMessage
        self.thankYouMessageHeader = thankYouMessageHeader
        self.thankYouMessageDescription = thankYouMessageDescription
        self.thankYouMessageDescriptionContentType = thankYouMessageDescriptionContentType
        self.thankYouMessageCloseButtonText = thankYouMessageCloseButtonText
        super.init()
    }
}
