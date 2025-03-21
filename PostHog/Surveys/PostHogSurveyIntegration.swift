//
//  PostHogSurveyIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

#if os(iOS) || TESTING

    import Foundation
    #if os(iOS)
        import UIKit
    #endif

    typealias SurveyResponse = String // TEMP:

    final class PostHogSurveyIntegration: PostHogIntegration {
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

        #if os(iOS)
            private var surveysWindow: UIWindow?
            private var surveyDisplayManager: SurveysDisplayController?
        #endif

        private var didBecomeActiveToken: RegistrationToken?

        func install(_ postHog: PostHogSDK) throws {
            try PostHogSurveyIntegration.integrationInstalledLock.withLock {
                if PostHogSurveyIntegration.integrationInstalled {
                    throw InternalPostHogError(description: "Replay integration already installed to another PostHogSDK instance.")
                }
                PostHogSurveyIntegration.integrationInstalled = true
            }

            self.postHog = postHog
            start()
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
            didBecomeActiveToken = DI.main.appLifecyclePublisher.onDidBecomeActive { [weak self] in
                guard let self else { return }

                #if os(iOS)
                    if let activeWindow = UIApplication.getCurrentWindow(), let activeScene = activeWindow.windowScene {
                        let surveyDisplayManager = SurveysDisplayController(
                            getNextSurveyStep: getNextSurveyStep,
                            onSurveySent: onSurveySent,
                            onSurveyDismissed: onSurveyDismissed
                        )
                        surveysWindow = SurveysWindow(
                            surveysManager: surveyDisplayManager,
                            scene: activeScene
                        )
                        surveysWindow?.isHidden = false
                        surveysWindow?.windowLevel = activeWindow.windowLevel + 1

                        self.surveyDisplayManager = surveyDisplayManager

                        // TEMP, testing display
                        let survey = Survey(
                            id: "my-survey-id",
                            name: "Survey Name",
                            type: .popover,
                            questions: [],
                            featureFlagKeys: nil,
                            linkedFlagKey: nil,
                            targetingFlagKey: nil,
                            internalTargetingFlagKey: nil,
                            conditions: nil,
                            appearance: nil,
                            currentIteration: nil,
                            currentIterationStartDate: nil,
                            startDate: nil,
                            endDate: nil
                        )

                        DispatchQueue.main.async {
                            surveyDisplayManager.showSurvey(survey)
                        }
                    }
                #endif
            }

            // TODO: listen to screen view events
            // TODO: listen to event capture events
        }

        func stop() {
            didBecomeActiveToken = nil
            #if os(iOS)
                surveysWindow?.rootViewController?.dismiss(animated: true) {
                    self.surveysWindow?.isHidden = true
                    self.surveysWindow = nil
                    self.surveyDisplayManager = nil
                }
            #endif
        }

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
                        .joined() // flatten
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

            guard let config = config, config.surveys else {
                hedgeLog("Surveys disabled. Not loading surveys.")
                return callback([])
            }

            // mem cache
            let allSurveys = allSurveysLock.withLock { self.allSurveys }

            if let allSurveys, !forceReload {
                callback(allSurveys)
            } else {
                // first or force load
                getRemoteConfig(remoteConfig, forceReload: forceReload) { [weak self] config in
                    self?.getFeatureFlags(remoteConfig, forceReload: forceReload) { [weak self] _ in
                        self?.decodeAndSetSurveys(remoteConfig: config, callback: callback)
                    }
                }
            }
        }

        private func getRemoteConfig(
            _ remoteConfig: PostHogRemoteConfig,
            forceReload: Bool = false,
            callback: (([String: Any]?) -> Void)? = nil
        ) {
            let cached = remoteConfig.getRemoteConfig()
            if cached == nil || forceReload {
                remoteConfig.reloadRemoteConfig(callback: callback)
            } else {
                callback?(cached)
            }
        }

        private func getFeatureFlags(
            _ remoteConfig: PostHogRemoteConfig,
            forceReload: Bool = false,
            callback: (([String: Any]?) -> Void)? = nil
        ) {
            let cached = remoteConfig.getFeatureFlags()
            if cached == nil || forceReload {
                remoteConfig.reloadFeatureFlags(callback: callback)
            } else {
                callback?(cached)
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

        private func getNextSurveyStep(
            survey _: Survey,
            currentQuestionIndex _: Int,
            response _: SurveyResponse
        ) -> Int {
            0
        }

        private func onSurveySent(survey: Survey) {
            // TODO: checks
            sendSurveySentEvent(survey: survey)
        }

        private func onSurveyDismissed(survey: Survey) {
            // TODO: checks
            sendSurveyDismissedEvent(survey: survey)
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
            // any of the targets contain the value (matched lowercase)
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
#endif
