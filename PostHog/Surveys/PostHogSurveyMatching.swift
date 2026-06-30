//
//  PostHogSurveyMatching.swift
//  PostHog
//
//  Created by PostHog Code on 2026-06-30.
//
//  Self-contained helper types used by `PostHogSurveyIntegration` for survey
//  state, condition matching, and rating bucketing. Kept in a separate file so
//  the integration stays within the file-length limit.
//

#if os(iOS) || TESTING

    import Foundation

    enum NextSurveyQuestion {
        case index(Int)
        case end
    }

    extension PostHogSurvey: CustomStringConvertible {
        var description: String {
            "\(name) [\(id)]"
        }
    }

    extension PostHogSurvey {
        var isActive: Bool {
            startDate != nil && endDate == nil
        }

        var hasEvents: Bool {
            conditions?.events?.values.count ?? 0 > 0
        }

        var canActivateRepeatedly: Bool {
            (conditions?.events?.repeatedActivation == true && hasEvents) ||
                schedule == .always
        }
    }

    extension PostHogSurveyMatchType {
        func matches(targets: [String], value: String) -> Bool {
            switch self {
            // value contains any of the targets (case-insensitive)
            case .iContains:
                targets.contains { target in
                    value.lowercased().contains(target.lowercased())
                }
            // value contains *none* of the targets (case-insensitive)
            case .notIContains:
                targets.allSatisfy { target in
                    !value.lowercased().contains(target.lowercased())
                }
            // value matches any of the targets as a regex pattern
            case .regex:
                targets.contains { target in
                    value.range(of: target, options: .regularExpression) != nil
                }
            // value matches *none* of the targets as a regex pattern
            case .notRegex:
                targets.allSatisfy { target in
                    value.range(of: target, options: .regularExpression) == nil
                }
            // any of the targets is an exact match
            case .exact:
                targets.contains { target in
                    target == value
                }
            // *none* of the targets is an exact match
            case .isNot:
                targets.allSatisfy { target in
                    target != value
                }
            // any of the targets is numerically less than the value (value > target)
            case .gt:
                targets.contains { target in
                    if let targetNum = Double(target), let valueNum = Double(value) {
                        return valueNum > targetNum
                    }
                    return false
                }
            // any of the targets is numerically greater than the value (value < target)
            case .lt:
                targets.contains { target in
                    if let targetNum = Double(target), let valueNum = Double(value) {
                        return valueNum < targetNum
                    }
                    return false
                }
            case .unknown:
                false
            }
        }
    }

    enum RatingBucket {
        // Bucket names
        static let negative = "negative"
        static let neutral = "neutral"
        static let positive = "positive"
        static let detractors = "detractors"
        static let passives = "passives"
        static let promoters = "promoters"

        // Scale ranges
        static let threePointRange = 1 ... 3
        static let fivePointRange = 1 ... 5
        static let sevenPointRange = 1 ... 7
        static let tenPointRange = 0 ... 10
    }

    enum BucketThresholds {
        enum ThreePoint {
            static let negatives = 1 ... 1
            static let neutrals = 2 ... 2
        }

        enum FivePoint {
            static let negatives = 1 ... 2
            static let neutrals = 3 ... 3
        }

        enum SevenPoint {
            static let negatives = 1 ... 3
            static let neutrals = 4 ... 4
        }

        enum TenPoint {
            static let detractors = 0 ... 6
            static let passives = 7 ... 8
        }
    }

#endif
