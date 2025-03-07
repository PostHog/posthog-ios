//
//  PostHogSurveyIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

import Foundation

final class PostHogSurveyIntegration {
    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false

    typealias SurveyCallback = (_ surveys: [Survey]) -> Void

    private let kSurveySeenKeyPrefix = "seenSurvey_"

    private var postHog: PostHogSDK?
    private var config: PostHogConfig? { postHog?.config }
    private var storage: PostHogStorage? { postHog?.storage }
    private var remoteConfig: PostHogRemoteConfig? { postHog?.remoteConfig }

    private var allSurveysLock = NSLock()
    private var allSurveys: [Survey]?

    private var activeSurveyLock = NSLock()
    private var activeSurvey: Survey?

    func install(_ postHog: PostHogSDK) throws {
        try PostHogSurveyIntegration.integrationInstalledLock.withLock {
            if PostHogSurveyIntegration.integrationInstalled {
                throw InternalPostHogError(description: "Replay integration already installed to another PostHogSDK instance.")
            }
            PostHogSurveyIntegration.integrationInstalled = true
        }

        self.postHog = postHog
    }

    func uninstall(_ postHog: PostHogSDK) {
        if self.postHog === postHog || self.postHog == nil {
            stop()
            self.postHog = nil
            PostHogSurveyIntegration.integrationInstalledLock.withLock {
                PostHogSurveyIntegration.integrationInstalled = false
            }
        }
    }

    func start() {
        //TODO: listen to screen view events
        //TODO: listen to event capture events
        //TODO: listen to app lifecycle events?
    }

    func stop() {}

    /// Get surveys that should be enabled for the current user
    func getActiveMatchingSurveys(
        forceReload: Bool = false,
        callback: @escaping SurveyCallback
    ) {
        getSurveys(forceReload: forceReload) { [weak self] surveys in
            guard let self else { return }

            let matchingSurveys = surveys
                .lazy
                .filter(\.isActive) // 1. active surveys,
                .filter { survey in // 2. that match display conditions,
                    // TODO: Check screen conditions
                    // TODO: Check event conditions
                    let deviceTypeCheck = self.doesSurveyDeviceTypesMatch(survey: survey)
                    return deviceTypeCheck
                }
                .filter { survey in // 3. that match linked flags
                    let allKeys: [String?] = [
                        [survey.linkedFlagKey],
                        [survey.targetingFlagKey],
                        // we check internal targeting flags only if this survey cannot be activated repeatedly
                        [survey.canActivateRepeatedly ? nil : survey.internalTargetingFlagKey],
                        survey.featureFlagKeys?.compactMap { kvp in
                            kvp.key.isEmpty ? nil : kvp.value
                        } ?? [],
                    ]
                    .joined()
                    .compactMap { $0 } // remove nils
                    .filter { !$0.isEmpty } // remove empty keys

                    return Set(allKeys) // remove dupes
                        .allSatisfy(self.isSurveyFeatureFlagEnabled) // all keys must be enabled
                }

            callback(Array(matchingSurveys))
        }
    }

    private func getSurveys(forceReload: Bool = false, callback: @escaping SurveyCallback) {
        guard let remoteConfig else {
            return
        }

        guard let config = config, config.surveysEnabled else {
            hedgeLog("Surveys disabled. Not loading surveys.")
            return callback([])
        }

        // mem cache
        let allSurveys = allSurveysLock.withLock { self.allSurveys }

        if let allSurveys, !forceReload {
            callback(allSurveys)
        } else {
            // first or force load
            remoteConfig.getRemoteConfigAsync(forceReload: forceReload) { [weak self] config in
                remoteConfig.getFeatureFlagsAsync(forceReload: forceReload) { [weak self] _ in
                    self?.decodeAndSetSurveys(remoteConfig: config, callback: callback)
                }
            }
        }
    }

    private func decodeAndSetSurveys(remoteConfig: [String: Any]?, callback: @escaping SurveyCallback) {
        let loadedSurveys: [Survey] = decodeSurveys(from: remoteConfig ?? [:])
        allSurveysLock.withLock {
            self.allSurveys = loadedSurveys
        }
        callback(loadedSurveys)
    }

    private func decodeSurveys(from remoteConfig: [String: Any]) -> [Survey] {
        guard let surveysJSON = remoteConfig["surveys"] else {
            return []
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: surveysJSON)
            return try PostHogApi.jsonDecoder.decode([Survey].self, from: jsonData)
        } catch {
            hedgeLog("Error decoding Surveys: \(error)")
            return []
        }
    }

    private func isSurveyFeatureFlagEnabled(flagKey: String?) -> Bool {
        guard let flagKey, let postHog else {
            return false
        }

        return postHog.isFeatureEnabled(flagKey)
    }

    private func canRenderSurvey(survey _: Survey) -> Bool {
        false
    }

    /// Sets given survey as active survey
    private func setActiveSurvey(survey: Survey) {
        activeSurveyLock.withLock {
            if let activeSurvey {
                hedgeLog("Survey \(activeSurvey) already in focus. Cannot add survey \(survey).")
                return
            }
            activeSurvey = survey
        }
    }

    /// Removes given survey as active survey
    private func removeActiveSurvey(survey: Survey) {
        activeSurveyLock.withLock {
            guard activeSurvey?.id != survey.id else {
                hedgeLog("Survey \(survey) is not in focus. Cannot remove survey \(survey)")
                return
            }
            activeSurvey = nil
        }
    }

    /// Returns the computed storage key for a given survey
    private func getSurveySeenKey(_ survey: Survey) -> String {
        let surveySeenKey = "\(kSurveySeenKeyPrefix)\(survey.id)"
        if let currentIteration = survey.currentIteration, currentIteration > 0 {
            return "\(surveySeenKey)_\(currentIteration)"
        }
        return surveySeenKey
    }

    /// Checks storage for seenSurvey_ key and returns its value
    ///
    /// Note: if the survey can be repeatedly activated by its events, or if the key is missing, this value will default to false
    private func getSurveySeen(survey: Survey) -> Bool {
        if survey.canActivateRepeatedly {
            // if this survey can activate repeatedly, we override this return value
            return false
        }

        let key = getSurveySeenKey(survey)
        let surveysSeen = storage?.getDictionary(forKey: .surveySeen) ?? [:]
        let surveySeen = surveysSeen[key] as? Bool ?? false

        return surveySeen
    }

    /// Returns given url match type or default value if nil
    private func getMatchTypeOrDefault(_ matchType: SurveyMatchType?) -> SurveyMatchType {
        matchType ?? .iContains
    }

    private func doesSurveyDeviceTypesMatch(survey: Survey) -> Bool {
        guard
            let conditions = survey.conditions,
            let deviceTypes = conditions.deviceTypes, deviceTypes.count > 0
        else {
            // not device type restrictions, assume true
            return true
        }

        guard
            let deviceType = PostHogContext.deviceType
        else {
            // if we don't know the current device type, we assume it is not a match
            return false
        }

        let matchType = getMatchTypeOrDefault(conditions.deviceTypesMatchType)

        return matchType.matches(targets: deviceTypes, value: deviceType)
    }

    /// Sends a `survey shown` event to PostHog instance
    private func sendSurveyShownEvent(survey _: Survey) {
        guard let postHog else {
            hedgeLog("[survey shown] event not captured, PostHog instance not found.")
            return
        }
        // TODO: this is where we set lastSeenSurveyDate on storage
        
        hedgeLog("[survey shown] Should send event")
    }

    /// Sends a `survey dismissed` event to PostHog instance
    private func sendSurveyDismissedEvent(survey _: Survey) {
        guard let postHog else {
            hedgeLog("[survey dismissed] event not captured, PostHog instance not found.")
            return
        }
        // TODO: this is where we set seenSurvey_ on storage
        
        hedgeLog("[survey dismissed] Should send event")
    }

    /// Sends a `survey sent` event to PostHog instance
    private func sendSurveySentEvent(survey _: Survey) {
        guard let postHog else {
            hedgeLog("[survey sent] event not captured, PostHog instance not found.")
            return
        }

        // TODO: this is where we set seenSurvey_ on storage

        hedgeLog("[survey sent] Should send event")
    }
}

extension Survey: CustomStringConvertible {
    var description: String {
        "\(name) [\(id)]"
    }
}

extension Survey {
    var isActive: Bool {
        startDate != nil && endDate == nil
    }

    var hasEvents: Bool {
        conditions?.events?.values.count ?? 0 > 0
    }

    var canActivateRepeatedly: Bool {
        conditions?.events?.repeatedActivation == true && hasEvents
    }
}

private extension SurveyMatchType {
    func matches(targets: [String], value: String) -> Bool {
        switch self {
        // any if the targets contain the value (matched lowercase)
        case .iContains:
            targets.contains { target in
                target.lowercased().contains(value.lowercased())
            }
        // *none* of the targets contain the value (matched lowercase)
        case .notIContains:
            targets.allSatisfy { target in
                !target.lowercased().contains(value.lowercased())
            }
        // any of the targets match with regex
        case .regex:
            targets.contains { target in
                target.range(of: value, options: .regularExpression) != nil
            }
        // *none* if the targets match with regex
        case .notRegex:
            targets.allSatisfy { target in
                target.range(of: value, options: .regularExpression) == nil
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
        }
    }
}

#if TESTING
    extension SurveyMatchType {
        var matchFunction: (_ targets: [String], _ value: String) -> Bool {
            matches
        }
    }

    extension PostHogSurveyIntegration {
        func setSurveys(_ surveys: [Survey]) {
            allSurveys = surveys
        }

        static func clearInstalls() {
            integrationInstalledLock.withLock {
                integrationInstalled = false
            }
        }
    }
#endif
