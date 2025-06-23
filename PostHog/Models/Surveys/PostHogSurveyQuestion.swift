//
//  PostHogSurveyQuestion.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

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
    case unknown(type: String)

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
        case let .unknown(type):
            self = .unknown(type: type)
        }
    }

    var question: String {
        wrappedQuestion?.question ?? ""
    }

    var description: String? {
        wrappedQuestion?.description
    }

    var descriptionContentType: PostHogSurveyTextContentType? {
        wrappedQuestion?.descriptionContentType
    }

    var optional: Bool? {
        wrappedQuestion?.optional
    }

    var buttonText: String? {
        wrappedQuestion?.buttonText
    }

    var originalQuestionIndex: Int? {
        wrappedQuestion?.originalQuestionIndex
    }

    var branching: PostHogSurveyQuestionBranching? {
        wrappedQuestion?.branching
    }

    private var wrappedQuestion: PostHogSurveyQuestionProperties? {
        switch self {
        case let .open(question): question
        case let .link(question): question
        case let .rating(question): question
        case let .singleChoice(question): question
        case let .multipleChoice(question): question
        case .unknown: nil
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
    let link: String?
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
    let scale: PostHogSurveyRatingScale
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

/// Represents branching logic for a question based on user responses
enum PostHogSurveyQuestionBranching: Decodable {
    case next
    case end
    case responseBased(responseValues: [String: Any])
    case specificQuestion(index: Int)
    case unknown(type: String)

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
        case let .unknown(type):
            self = .unknown(type: type)
        }
    }

    private enum CodingKeys: CodingKey {
        case type, responseValues, index
    }
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
