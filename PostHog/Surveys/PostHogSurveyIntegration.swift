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

        private var eventsToSurveysLock = NSLock()
        private var eventsToSurveys: [String: [String]] = [:]

        private var seenSurveyKeysLock = NSLock()
        private var seenSurveyKeys: [AnyHashable: Any]?

        private var activeSurveyLock = NSLock()
        private var activeSurvey: Survey?

        private var eventActivatedSurveysLock = NSLock()
        private var eventActivatedSurveys: Set<String> = []

        #if os(iOS)
            private var surveysWindow: UIWindow?
            private var surveyDisplayManager: SurveyDisplayController?
        #endif

        private var didBecomeActiveToken: RegistrationToken?
        private var didLayoutViewToken: RegistrationToken?

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
            #if os(iOS)
                if #available(iOS 15.0, *) {
                    // TODO: listen to screen view events

                    didLayoutViewToken = DI.main.viewLayoutPublisher.onViewLayout(throttle: 5) { [weak self] in
                        self?.showNextSurvey()
                    }

                    didBecomeActiveToken = DI.main.appLifecyclePublisher.onDidBecomeActive { [weak self] in
                        guard let self, surveysWindow == nil else { return }

                        #if os(iOS)
                            if let activeWindow = UIApplication.getCurrentWindow(), let activeScene = activeWindow.windowScene {
                                let surveyDisplayManager = SurveyDisplayController(
                                    onSurveyShown: onSurveyShown,
                                    onSurveyResponse: onSurveyResponse,
                                    onSurveyClosed: onSurveyClosed
                                )

                                surveysWindow = SurveysWindow(
                                    surveysManager: surveyDisplayManager,
                                    scene: activeScene
                                )
                                surveysWindow?.isHidden = false
                                surveysWindow?.windowLevel = activeWindow.windowLevel + 1

                                self.surveyDisplayManager = surveyDisplayManager

                                showNextSurvey()
                            }
                        #endif
                    }
                }
            #endif
        }

        func stop() {
            didBecomeActiveToken = nil
            didLayoutViewToken = nil
            #if os(iOS)
                surveysWindow?.rootViewController?.dismiss(animated: true) {
                    self.surveysWindow?.isHidden = true
                    self.surveysWindow = nil
                    self.surveyDisplayManager = nil
                }
            #endif
        }

        /// Get surveys enabled for the current user
        func getActiveMatchingSurveys(
            forceReload: Bool = false,
            callback: @escaping SurveyCallback
        ) {
            getSurveys(forceReload: forceReload) { [weak self] surveys in
                guard let self else { return }

                let matchingSurveys = surveys
                    .lazy
                    .filter { // 1. unseen surveys,
                        !self.getSurveySeen(survey: $0)
                    }
                    .filter(\.isActive) // 2. that are active,
                    .filter { survey in // 3. and match display conditions,
                        // TODO: Check screen conditions
                        // TODO: Check event conditions
                        let deviceTypeCheck = self.doesSurveyDeviceTypesMatch(survey: survey)
                        return deviceTypeCheck
                    }
                    .filter { survey in // 4. and match linked flags
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
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }

                        // all keys must be enabled
                        return Set(allKeys)
                            .allSatisfy(self.isSurveyFeatureFlagEnabled)
                    }
                    .filter { survey in // 5. and if event-based, have been activated by that event
                        survey.hasEvents ? self.isSurveyEventActivated(survey: survey) : true
                    }

                callback(Array(matchingSurveys))
            }
        }

        // TODO: Decouple PostHogSDK and use registration handlers instead
        /// Called from PostHogSDK instance when an event is captured
        func onEvent(event: String) {
            let activatedSurveys = eventsToSurveysLock.withLock { eventsToSurveys[event] } ?? []
            guard !activatedSurveys.isEmpty else { return }

            eventActivatedSurveysLock.withLock {
                for survey in activatedSurveys {
                    eventActivatedSurveys.insert(survey)
                }
            }

            DispatchQueue.main.async {
                self.showNextSurvey()
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

            let eventMap = loadedSurveys.reduce(into: [String: [String]]()) { result, current in
                if let surveyEvents = current.conditions?.events?.values.map(\.name) {
                    for event in surveyEvents {
                        result[event, default: []].append(current.id)
                    }
                }
            }

            allSurveysLock.withLock {
                self.allSurveys = loadedSurveys
            }
            eventsToSurveysLock.withLock {
                self.eventsToSurveys = eventMap
            }

            callback(loadedSurveys)
        }

        private func decodeSurveys(from remoteConfig: [String: Any]) -> [Survey] {
            guard let surveysJSON = remoteConfig["surveys"] as? [[String: Any]] else {
                // surveys not json, disabled
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

        private func canRenderSurvey(survey: Survey) -> Bool {
            // only render popover surveys for now
            survey.type == .popover
        }

        /// Shows next survey in queue. No-op if a survey is already being shown
        private func showNextSurvey() {
            guard surveyDisplayManager?.canShowNextSurvey() == true else { return }

            // Check if there is a new popover surveys to be displayed
            getActiveMatchingSurveys { activeSurveys in
                if let survey = activeSurveys.first(where: self.canRenderSurvey) {
                    DispatchQueue.main.async { [weak self] in
                        self?.surveyDisplayManager?.showSurvey(survey)
                    }
                }
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
            let surveysSeen = getSeenSurveyKeys()
            let surveySeen = surveysSeen[key] as? Bool ?? false

            return surveySeen
        }

        /// Mark a survey as seen
        private func setSurveySeen(survey: Survey) {
            let key = getSurveySeenKey(survey)
            let seenKeys = seenSurveyKeysLock.withLock {
                seenSurveyKeys?[key] = true
                return seenSurveyKeys
            }

            storage?.setDictionary(forKey: .surveySeen, contents: seenKeys ?? [:])
        }

        /// Returns survey seen list (and mem-cache from disk if needed)
        private func getSeenSurveyKeys() -> [AnyHashable: Any] {
            seenSurveyKeysLock.withLock {
                if seenSurveyKeys == nil {
                    seenSurveyKeys = storage?.getDictionary(forKey: .surveySeen) ?? [:]
                }
                return seenSurveyKeys ?? [:]
            }
        }

        /// Returns given match type or default value if nil
        private func getMatchTypeOrDefault(_ matchType: SurveyMatchType?) -> SurveyMatchType {
            matchType ?? .iContains
        }

        /// Checks if a survey with a device type condition matches the current device type
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

        /// Checks if a survey has been previously activated by an associated event
        private func isSurveyEventActivated(survey: Survey) -> Bool {
            eventActivatedSurveysLock.withLock {
                eventActivatedSurveys.contains(survey.id)
            }
        }

        /// Handle a survey that is shown
        private func onSurveyShown(survey: Survey) {
            sendSurveyShownEvent(survey: survey)

            // clear up event-activated surveys
            if survey.hasEvents {
                eventActivatedSurveysLock.withLock {
                    _ = eventActivatedSurveys.remove(survey.id)
                }
            }
        }

        /// Handle a survey response
        private func onSurveyResponse(survey: Survey, responses: [String: SurveyResponse], completed: Bool) {
            // TODO: Partial responses
            if completed {
                sendSurveySentEvent(survey: survey, responses: responses)

                // Auto-hide if a confirmation message is not displayed
                if survey.appearance?.displayThankYouMessage == false {
                    surveyDisplayManager?.dismissSurvey()
                }
            }
        }

        /// Handle a survey dismiss
        private func onSurveyClosed(survey: Survey, completed: Bool) {
            if !completed {
                sendSurveyDismissedEvent(survey: survey)
            }
            // mark seen
            setSurveySeen(survey: survey)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                // show next survey in queue, if any, after a short delay
                self.showNextSurvey()
            }
        }

        /// Sends a `survey shown` event to PostHog instance
        private func sendSurveyShownEvent(survey: Survey) {
            sendSurveyEvent(
                event: "survey shown",
                survey: survey
            )
        }

        /// Sends a `survey sent` event to PostHog instance
        private func sendSurveySentEvent(survey: Survey, responses: [String: SurveyResponse]) {
            let questionProperties: [String: Any] = [
                "$survey_questions": survey.questions.map(\.question),
                "$set": [getSurveyInteractionProperty(survey: survey, property: "responded"): true],
            ]

            let responsesProperties: [String: Any] = responses.mapValues { resp in
                switch resp {
                case let .link(link): link
                case let .multipleChoice(choices): choices
                case let .singleChoice(choice): choice
                case let .openEnded(input): input
                case let .rating(rating): "\(rating)"
                }
            }

            let additionalProperties = questionProperties.merging(responsesProperties, uniquingKeysWith: { _, new in new })

            sendSurveyEvent(
                event: "survey sent",
                survey: survey,
                additionalProperties: additionalProperties
            )
        }

        /// Sends a `survey dismissed` event to PostHog instance
        private func sendSurveyDismissedEvent(survey: Survey) {
            let additionalProperties: [String: Any] = [
                "$survey_questions": survey.questions.map(\.question),
                "$set": [
                    getSurveyInteractionProperty(survey: survey, property: "dismissed"): true,
                ],
            ]

            sendSurveyEvent(
                event: "survey dismissed",
                survey: survey,
                additionalProperties: additionalProperties
            )
        }

        private func sendSurveyEvent(event: String, survey: Survey, additionalProperties: [String: Any] = [:]) {
            guard let postHog else {
                hedgeLog("[\(event)] event not captured, PostHog instance not found.")
                return
            }

            var properties = getBaseSurveyEventProperties(for: survey)
            properties.merge(additionalProperties) { _, new in new }

            postHog.capture(event, properties: properties)
        }

        private func getBaseSurveyEventProperties(for survey: Survey) -> [String: Any] {
            // TODO: Add session replay screen name
            let props: [String: Any?] = [
                "$survey_name": survey.name,
                "$survey_id": survey.id,
                "$survey_iteration": survey.currentIteration,
                "$survey_iteration_start_date": survey.currentIterationStartDate.map(toISO8601String),
            ]
            return props.compactMapValues { $0 }
        }

        private func getSurveyInteractionProperty(survey: Survey, property: String) -> String {
            var surveyProperty = "$survey_\(property)/\(survey.id)"

            if let currentIteration = survey.currentIteration, currentIteration > 0 {
                surveyProperty = "$survey_\(property)/\(survey.id)/\(currentIteration)"
            }

            return surveyProperty
        }
    }

    extension Survey: CustomStringConvertible {
        var description: String {
            "\(name) [\(id)]"
        }
    }

    private extension Survey {
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
