//
//  PostHogSurveyEnums.swift
//  PostHog
//
//  Created by Ioannis Josephides on 08/04/2025.
//

import Foundation

private func decodeSurveyStringValue<T>(
    from decoder: any Decoder,
    values: [String: T],
    unknown: (String) -> T
) throws -> T {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    return values[value] ?? unknown(value)
}

// MARK: - Supporting Types

enum PostHogSurveyType: Decodable, Equatable {
    case popover
    case api
    case widget
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "popover": .popover,
                "api": .api,
                "widget": .widget,
            ]
        ) { .unknown(type: $0) }
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
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "open": .open,
                "link": .link,
                "rating": .rating,
                "multiple_choice": .multipleChoice,
                "single_choice": .singleChoice,
            ]
        ) { .unknown(type: $0) }
    }
}

enum PostHogSurveyTextContentType: Decodable, Equatable {
    case html
    case text
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "html": .html,
                "text": .text,
            ]
        ) { .unknown(type: $0) }
    }
}

enum PostHogSurveyMatchType: Decodable, Equatable {
    case regex
    case notRegex
    case exact
    case isNot
    case iContains
    case notIContains
    case gt
    case lt
    case unknown(value: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "regex": .regex,
                "not_regex": .notRegex,
                "exact": .exact,
                "is_not": .isNot,
                "icontains": .iContains,
                "not_icontains": .notIContains,
                "gt": .gt,
                "lt": .lt,
            ]
        ) { .unknown(value: $0) }
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
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "top_left": .topLeft,
                "top_center": .topCenter,
                "top_right": .topRight,
                "middle_left": .middleLeft,
                "middle_center": .middleCenter,
                "middle_right": .middleRight,
                "left": .left,
                "right": .right,
                "center": .center,
            ]
        ) { .unknown(position: $0) }
    }
}

enum PostHogSurveyAppearanceWidgetType: Decodable, Equatable {
    case button
    case tab
    case selector
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "button": .button,
                "tab": .tab,
                "selector": .selector,
            ]
        ) { .unknown(type: $0) }
    }
}

enum PostHogSurveyRatingDisplayType: Decodable, Equatable {
    case number
    case emoji
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "number": .number,
                "emoji": .emoji,
            ]
        ) { .unknown(type: $0) }
    }
}

enum PostHogSurveyRatingScale: Decodable, Equatable {
    case twoPoint
    case threePoint
    case fivePoint
    case sevenPoint
    case tenPoint
    case unknown(scale: Int)

    var rawValue: Int {
        switch self {
        case .twoPoint: 2
        case .threePoint: 3
        case .fivePoint: 5
        case .sevenPoint: 7
        case .tenPoint: 10
        case let .unknown(scale): scale
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .twoPoint: 1 ... 2
        case .threePoint: 1 ... 3
        case .fivePoint: 1 ... 5
        case .sevenPoint: 1 ... 7
        case .tenPoint: 0 ... 10
        case let .unknown(scale): 1 ... scale
        }
    }

    init(range: ClosedRange<Int>) {
        switch range {
        case 1 ... 2: self = .twoPoint
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
        case 2:
            self = .twoPoint
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

enum PostHogSurveySchedule: Decodable, Equatable {
    case once
    case recurring
    case always
    case unknown(schedule: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "once": .once,
                "recurring": .recurring,
                "always": .always,
            ]
        ) { .unknown(schedule: $0) }
    }
}

enum PostHogSurveyQuestionBranchingType: Decodable, Equatable {
    case nextQuestion
    case end
    case responseBased
    case specificQuestion
    case unknown(type: String)

    init(from decoder: any Decoder) throws {
        self = try decodeSurveyStringValue(
            from: decoder,
            values: [
                "next_question": .nextQuestion,
                "end": .end,
                "response_based": .responseBased,
                "specific_question": .specificQuestion,
            ]
        ) { .unknown(type: $0) }
    }
}
