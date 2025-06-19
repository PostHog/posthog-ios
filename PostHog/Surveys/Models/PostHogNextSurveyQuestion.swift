//
//  PostHogNextSurveyQuestion.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/06/2025.
//

import Foundation

/// A model representing the next state of the survey progression.
@objc public class PostHogNextSurveyQuestion: NSObject {
    /// The index of the next question to be displayed (0-based)
    public let questionIndex: Int
    /// Whether all questions have been answered and the survey is complete
    /// Depending on the survey appearance configuration, you may want to show the "Thank you" message or dismiss the survey at this point
    public let isSurveyCompleted: Bool

    init(questionIndex: Int, isSurveyCompleted: Bool) {
        self.questionIndex = questionIndex
        self.isSurveyCompleted = isSurveyCompleted
        super.init()
    }
}
