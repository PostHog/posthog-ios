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

        var requiresFeatureFlagEvaluation: Bool {
            let keys = [linkedFlagKey, targetingFlagKey, canActivateRepeatedly ? nil : internalTargetingFlagKey] +
                (featureFlagKeys?.map(\.value) ?? [])
            return keys.contains { !($0?.isEmpty ?? true) }
        }
    }

    extension PostHogSurveyIntegration {
        func decodeAndSetSurveys(
            remoteConfig: [String: Any]?,
            beforeCacheUpdate: SurveyCallback? = nil,
            callback: @escaping SurveyCallback
        ) {
            let loadedSurveys: [PostHogSurvey] = decodeSurveys(from: remoteConfig ?? [:])
            beforeCacheUpdate?(loadedSurveys)

            let eventMap = loadedSurveys.reduce(into: [String: [(surveyId: String, condition: PostHogEventCondition)]]()) { result, current in
                if let surveyEvents = current.conditions?.events?.values {
                    for eventCondition in surveyEvents {
                        result[eventCondition.name, default: []].append(
                            (surveyId: current.id, condition: eventCondition)
                        )
                    }
                }
            }

            updateSurveyCache(loadedSurveys, events: eventMap)
            callback(loadedSurveys)
        }

        func decodeSurveys(from remoteConfig: [String: Any]) -> [PostHogSurvey] {
            guard let surveysJSON = remoteConfig["surveys"] as? [[String: Any]] else {
                // surveys not json, disabled
                return []
            }

            // Decode each survey individually so one malformed entry doesn't drop the entire list
            return surveysJSON.compactMap { surveyJSON in
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: surveyJSON)
                    return try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: jsonData)
                } catch {
                    hedgeLog("Error decoding Survey: \(error)")
                    return nil
                }
            }
        }

        func canRenderSurvey(survey: PostHogSurvey) -> Bool {
            // only render popover surveys for now
            survey.type == .popover
        }

        var canShowSurveyWithFreshFeatureFlags: Bool {
            freshFeatureFlagsLock.withLock { surveyAwaitingFeatureFlagsGeneration == nil }
        }

        func subscribeToRemoteConfigUpdates() {
            remoteConfigLoadedToken = postHog?.remoteConfig?.onRemoteConfigLoaded.subscribe { [weak self] remoteConfig in
                guard let self, let remoteConfig else { return }
                self.decodeAndSetSurveys(
                    remoteConfig: remoteConfig,
                    beforeCacheUpdate: { surveys in self.refreshFeatureFlagsIfNeeded(for: surveys) },
                    callback: { _ in
                        if self.canShowSurveyWithFreshFeatureFlags { self.showNextSurvey() }
                    }
                )
            }
        }

        func unsubscribeFromRemoteConfigUpdates() {
            remoteConfigLoadedToken = nil
            freshFeatureFlagsLock.withLock {
                surveyRefreshGeneration += 1
                surveyAwaitingFeatureFlagsGeneration = nil
            }
        }

        func refreshFeatureFlagsIfNeeded(for surveys: [PostHogSurvey]) {
            let needsFlags = surveys.contains(where: \.requiresFeatureFlagEvaluation)
            let generation = freshFeatureFlagsLock.withLock {
                surveyRefreshGeneration += 1
                surveyAwaitingFeatureFlagsGeneration = needsFlags ? surveyRefreshGeneration : nil
                return surveyAwaitingFeatureFlagsGeneration
            }
            guard let generation else { return }

            postHog?.remoteConfig?.reloadFeatureFlags { [weak self] flags in
                guard let self, flags != nil else { return }
                DispatchQueue.main.async {
                    let shouldShow = self.freshFeatureFlagsLock.withLock {
                        guard self.surveyAwaitingFeatureFlagsGeneration == generation else { return false }
                        self.surveyAwaitingFeatureFlagsGeneration = nil
                        return true
                    }
                    if shouldShow { self.showNextSurvey() }
                }
            }
        }

        func reconcileEventActivations(with surveys: [PostHogSurvey]) {
            let current = surveys.reduce(into: [String: [PostHogEventCondition]]()) {
                $0[$1.id] = $1.conditions?.events?.values ?? []
            }
            eventActivatedSurveysLock.withLock {
                eventActivatedSurveys = eventActivatedSurveys.reduce(into: [:]) { result, activation in
                    let retained = activation.value.filter { current[activation.key]?.contains($0) == true }
                    if !retained.isEmpty { result[activation.key] = retained }
                }
            }
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
