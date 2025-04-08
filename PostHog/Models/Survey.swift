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
}

struct PostHogSurveyFeatureFlagKeyValue: Equatable, Decodable {
    let key: String
    let value: String?
}

// MARK: - Question Models

/// Protocol defining common properties for all survey question types
protocol PostHogSurveyQuestionProperties {
    /// Question text
    var question: String { get }
    /// Additional description or instructions (optional)
    var description: String? { get }
    /// Content type of the description (e.g., "text", "html") (optional)
    var descriptionContentType: PostHogSurveyTextContentType? { get }
    /// Indicates if this question is optional (optional)
    var optional: Bool? { get }
    /// Text for the main CTA associated with this question (optional)
    var buttonText: String? { get }
    /// Original index of the question in the survey (optional)
    var originalQuestionIndex: Int? { get }
    /// Question branching logic if any (optional)
    var branching: PostHogSurveyQuestionBranching? { get }
}

/// Represents different types of survey questions with their associated data
enum PostHogSurveyQuestion: PostHogSurveyQuestionProperties, Decodable {
    case open(PostHogOpenSurveyQuestion)
    case link(PostHogLinkSurveyQuestion)
    case rating(PostHogRatingSurveyQuestion)
    case singleChoice(PostHogMultipleSurveyQuestion)
    case multipleChoice(PostHogMultipleSurveyQuestion)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PostHogSurveyQuestionType.self, forKey: .type)

        switch type {
        case .open:
            self = try .open(PostHogOpenSurveyQuestion(from: decoder))
        case .link:
            self = try .link(PostHogLinkSurveyQuestion(from: decoder))
        case .rating:
            self = try .rating(PostHogRatingSurveyQuestion(from: decoder))
        case .singleChoice:
            self = try .singleChoice(PostHogMultipleSurveyQuestion(from: decoder))
        case .multipleChoice:
            self = try .multipleChoice(PostHogMultipleSurveyQuestion(from: decoder))
        }
    }

    var question: String {
        wrappedQuestion.question
    }

    var description: String? {
        wrappedQuestion.description
    }

    var descriptionContentType: PostHogSurveyTextContentType? {
        wrappedQuestion.descriptionContentType
    }

    var optional: Bool? {
        wrappedQuestion.optional
    }

    var buttonText: String? {
        wrappedQuestion.buttonText
    }

    var originalQuestionIndex: Int? {
        wrappedQuestion.originalQuestionIndex
    }

    var branching: PostHogSurveyQuestionBranching? {
        wrappedQuestion.branching
    }

    private var wrappedQuestion: PostHogSurveyQuestionProperties {
        switch self {
        case let .open(question): question
        case let .link(question): question
        case let .rating(question): question
        case let .singleChoice(question): question
        case let .multipleChoice(question): question
        }
    }

    private enum CodingKeys: CodingKey {
        case type
    }
}

/// Represents a basic open-ended survey question
struct PostHogOpenSurveyQuestion: PostHogSurveyQuestionProperties, Decodable {
    let question: String
    let description: String?
    let descriptionContentType: PostHogSurveyTextContentType?
    let optional: Bool?
    let buttonText: String?
    let originalQuestionIndex: Int?
    let branching: PostHogSurveyQuestionBranching?
}

/// Represents a survey question with an associated link
struct PostHogLinkSurveyQuestion: PostHogSurveyQuestionProperties, Decodable {
    let question: String
    let description: String?
    let descriptionContentType: PostHogSurveyTextContentType?
    let optional: Bool?
    let buttonText: String?
    let originalQuestionIndex: Int?
    let branching: PostHogSurveyQuestionBranching?
    /// URL link associated with the question
    let link: String
}

/// Represents a rating-based survey question
struct PostHogRatingSurveyQuestion: PostHogSurveyQuestionProperties, Decodable {
    let question: String
    let description: String?
    let descriptionContentType: PostHogSurveyTextContentType?
    let optional: Bool?
    let buttonText: String?
    let originalQuestionIndex: Int?
    let branching: PostHogSurveyQuestionBranching?
    /// Display type for the rating ("number" or "emoji")
    let display: PostHogSurveyRatingDisplayType
    /// Scale of the rating (3, 5, 7, or 10)
    let scale: Int
    let lowerBoundLabel: String
    let upperBoundLabel: String
}

/// Represents a multiple-choice or single-choice survey question
struct PostHogMultipleSurveyQuestion: PostHogSurveyQuestionProperties, Decodable {
    let question: String
    let description: String?
    let descriptionContentType: PostHogSurveyTextContentType?
    let optional: Bool?
    let buttonText: String?
    let originalQuestionIndex: Int?
    let branching: PostHogSurveyQuestionBranching?
    /// List of choices for multiple-choice or single-choice questions
    let choices: [String]
    /// Indicates if there is an open choice option (optional)
    let hasOpenChoice: Bool?
    /// Indicates if choices should be shuffled or not (optional)
    let shuffleOptions: Bool?
}

// MARK: - Branching Models

/// Represents branching logic for a question based on user responses
enum PostHogSurveyQuestionBranching: Decodable {
    case next
    case end
    case responseBased(responseValues: [String: Any])
    case specificQuestion(index: Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PostHogSurveyQuestionBranchingType.self, forKey: .type)

        switch type {
        case .nextQuestion:
            self = .next
        case .end:
            self = .end
        case .responseBased:
            do {
                let responseValues = try container.decode(JSON.self, forKey: .responseValues)
                guard let dict = responseValues.value as? [String: Any] else {
                    throw DecodingError.typeMismatch(
                        [String: Any].self,
                        DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription: "Expected responseValues to be a dictionary"
                        )
                    )
                }
                self = .responseBased(responseValues: dict)
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .responseValues,
                    in: container,
                    debugDescription: "responseValues is not a valid JSON object"
                )
            }
        case .specificQuestion:
            self = try .specificQuestion(index: container.decode(Int.self, forKey: .index))
        }
    }

    private enum CodingKeys: CodingKey {
        case type, responseValues, index
    }
}

// MARK: - Display Conditions

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
    public let repeatedActivation: Bool?
    /// List of events that trigger the survey
    public let values: [PostHogEventCondition]
}

struct PostHogSurveyActionsConditions: Decodable {
    /// List of events that trigger the survey
    public let values: [PostHogEventCondition]
}

/// Represents a single event condition used in survey targeting
struct PostHogEventCondition: Decodable, Equatable {
    /// Name of the event (e.g., "content loaded")
    public let name: String
}

// MARK: - Appearance

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

/// A helper type for decoding JSON values, which may be nested objects, arrays, strings, numbers, booleans, or nulls.
private struct JSON: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let object = try? container.decode([String: JSON].self) {
            value = object.mapValues { $0.value }
        } else if let array = try? container.decode([JSON].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let number = try? container.decode(Double.self) {
            value = NSNumber(value: number)
        } else if let number = try? container.decode(Int.self) {
            value = NSNumber(value: number)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid JSON value"
            )
        }
    }
}
