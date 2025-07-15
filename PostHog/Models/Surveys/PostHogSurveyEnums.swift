//
//  PostHogSurveyEnums.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

// MARK: - Supporting Types

enum PostHogSurveyType: Decodable, Equatable {
    case popover
    case api
    case widget
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)

        switch typeString {
        case "popover":
            self = .popover
        case "api":
            self = .api
        case "widget":
            self = .widget
        default:
            self = .unknown(type: typeString)
        }
    }
}

enum PostHogSurveyQuestionType: Decodable, Equatable {
    case open
    case link
    case rating
    case multipleChoice
    case singleChoice
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)

        switch typeString {
        case "open":
            self = .open
        case "link":
            self = .link
        case "rating":
            self = .rating
        case "multiple_choice":
            self = .multipleChoice
        case "single_choice":
            self = .singleChoice
        default:
            self = .unknown(type: typeString)
        }
    }
}

enum PostHogSurveyTextContentType: Decodable, Equatable {
    case html
    case text
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)

        switch typeString {
        case "html":
            self = .html
        case "text":
            self = .text
        default:
            self = .unknown(type: typeString)
        }
    }
}

enum PostHogSurveyMatchType: Decodable, Equatable {
    case regex
    case notRegex
    case exact
    case isNot
    case iContains
    case notIContains
    case unknown(value: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let valueString = try container.decode(String.self)

        switch valueString {
        case "regex":
            self = .regex
        case "not_regex":
            self = .notRegex
        case "exact":
            self = .exact
        case "is_not":
            self = .isNot
        case "icontains":
            self = .iContains
        case "not_icontains":
            self = .notIContains
        default:
            self = .unknown(value: valueString)
        }
    }
}

enum PostHogSurveyAppearancePosition: Decodable, Equatable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleCenter
    case middleRight
    case left
    case right
    case center
    case unknown(position: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let positionString = try container.decode(String.self)

        switch positionString {
        case "top_left":
            self = .topLeft
        case "top_center":
            self = .topCenter
        case "top_right":
            self = .topRight
        case "middle_left":
            self = .middleLeft
        case "middle_center":
            self = .middleCenter
        case "middle_right":
            self = .middleRight
        case "left":
            self = .left
        case "right":
            self = .right
        case "center":
            self = .center
        default:
            self = .unknown(position: positionString)
        }
    }
}

enum PostHogSurveyAppearanceWidgetType: Decodable, Equatable {
    case button
    case tab
    case selector
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)

        switch typeString {
        case "button":
            self = .button
        case "tab":
            self = .tab
        case "selector":
            self = .selector
        default:
            self = .unknown(type: typeString)
        }
    }
}

enum PostHogSurveyRatingDisplayType: Decodable, Equatable {
    case number
    case emoji
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)

        switch typeString {
        case "number":
            self = .number
        case "emoji":
            self = .emoji
        default:
            self = .unknown(type: typeString)
        }
    }
}

enum PostHogSurveyRatingScale: Decodable, Equatable {
    case threePoint
    case fivePoint
    case sevenPoint
    case tenPoint
    case unknown(scale: Int)

    var rawValue: Int {
        switch self {
        case .threePoint: 3
        case .fivePoint: 5
        case .sevenPoint: 7
        case .tenPoint: 10
        case let .unknown(scale): scale
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .threePoint: 1 ... 3
        case .fivePoint: 1 ... 5
        case .sevenPoint: 1 ... 7
        case .tenPoint: 0 ... 10
        case let .unknown(scale): 1 ... scale
        }
    }

    init(range: ClosedRange<Int>) {
        switch range {
        case 1 ... 3: self = .threePoint
        case 1 ... 5: self = .fivePoint
        case 1 ... 7: self = .sevenPoint
        case 0 ... 10: self = .tenPoint
        default: self = .unknown(scale: range.upperBound)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let scaleInt = try container.decode(Int.self)

        switch scaleInt {
        case 3:
            self = .threePoint
        case 5:
            self = .fivePoint
        case 7:
            self = .sevenPoint
        case 10:
            self = .tenPoint
        default:
            self = .unknown(scale: scaleInt)
        }
    }
}

enum PostHogSurveyQuestionBranchingType: Decodable, Equatable {
    case nextQuestion
    case end
    case responseBased
    case specificQuestion
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)

        switch typeString {
        case "next_question":
            self = .nextQuestion
        case "end":
            self = .end
        case "response_based":
            self = .responseBased
        case "specific_question":
            self = .specificQuestion
        default:
            self = .unknown(type: typeString)
        }
    }
}
