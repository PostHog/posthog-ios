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

        typealias SurveyCallback = (_ surveys: [PostHogSurvey]) -> Void

        private let kSurveySeenKeyPrefix = "seenSurvey_"
        private let kSurveyResponseKey = "$survey_response"

        private var postHog: PostHogSDK?
        private var config: PostHogConfig? { postHog?.config }
        private var storage: PostHogStorage? { postHog?.storage }
        private var remoteConfig: PostHogRemoteConfig? { postHog?.remoteConfig }

        private var allSurveysLock = NSLock()
        private var allSurveys: [PostHogSurvey]?

        private var eventsToSurveysLock = NSLock()
        private var eventsToSurveys: [String: [String]] = [:]

        private var seenSurveyKeysLock = NSLock()
        private var seenSurveyKeys: [AnyHashable: Any]?

        private var eventActivatedSurveysLock = NSLock()
        private var eventActivatedSurveys: Set<String> = []

        private var didBecomeActiveToken: RegistrationToken?
        private var didLayoutViewToken: RegistrationToken?

        private var activeSurveyLock = NSLock()
        private var activeSurvey: PostHogSurvey?
        private var activeSurveyResponses: [String: PostHogSurveyResponse] = [:] // keyed by question identifier
        private var activeSurveyCompleted: Bool = false
        private var activeSurveyQuestionIndex: Int = 0

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
                // TODO: listen to screen view events
                didLayoutViewToken = DI.main.viewLayoutPublisher.onViewLayout(throttle: 5) { [weak self] in
                    self?.showNextSurvey()
                }

                didBecomeActiveToken = DI.main.appLifecyclePublisher.onDidBecomeActive { [weak self] in
                    self?.showNextSurvey()
                }
            #endif
        }

        func stop() {
            didBecomeActiveToken = nil
            didLayoutViewToken = nil
            #if os(iOS)
                if #available(iOS 15.0, *) {
                    config?.surveysConfig.surveysDelegate.cleanupSurveys()
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

            guard let config = config, config._surveys else {
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
            let loadedSurveys: [PostHogSurvey] = decodeSurveys(from: remoteConfig ?? [:])

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

        private func decodeSurveys(from remoteConfig: [String: Any]) -> [PostHogSurvey] {
            guard let surveysJSON = remoteConfig["surveys"] as? [[String: Any]] else {
                // surveys not json, disabled
                return []
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: surveysJSON)
                return try PostHogApi.jsonDecoder.decode([PostHogSurvey].self, from: jsonData)
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

        private func canRenderSurvey(survey: PostHogSurvey) -> Bool {
            // only render popover surveys for now
            survey.type == .popover
        }

        /// Shows next survey in queue. No-op if a survey is already being shown
        private func showNextSurvey() {
            #if os(iOS)
                guard #available(iOS 15.0, *) else {
                    hedgeLog("[Surveys] Surveys can be rendered only on iOS 15+")
                    return
                }

                guard canShowNextSurvey() else { return }

                // Check if there is a new popover surveys to be displayed
                getActiveMatchingSurveys { activeSurveys in
                    if let survey = activeSurveys.first(where: self.canRenderSurvey) {
                        // set survey as active
                        self.setActiveSurvey(survey: survey)

                        DispatchQueue.main.async { [weak self] in
                            if let self {
                                // render the survey
                                self.postHog?.config.surveysConfig.surveysDelegate.renderSurvey(
                                    survey.toDisplaySurvey(),
                                    onSurveyShown: self.handleSurveyShown,
                                    onSurveyResponse: self.handleSurveyResponse,
                                    onSurveyClosed: self.handleSurveyClosed
                                )
                            }
                        }
                    }
                }
            #endif
        }

        /// Returns the computed storage key for a given survey
        private func getSurveySeenKey(_ survey: PostHogSurvey) -> String {
            let surveySeenKey = "\(kSurveySeenKeyPrefix)\(survey.id)"
            if let currentIteration = survey.currentIteration, currentIteration > 0 {
                return "\(surveySeenKey)_\(currentIteration)"
            }
            return surveySeenKey
        }

        /// Checks storage for seenSurvey_ key and returns its value
        ///
        /// Note: if the survey can be repeatedly activated by its events, or if the key is missing, this value will default to false
        private func getSurveySeen(survey: PostHogSurvey) -> Bool {
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
        private func setSurveySeen(survey: PostHogSurvey) {
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
        private func getMatchTypeOrDefault(_ matchType: PostHogSurveyMatchType?) -> PostHogSurveyMatchType {
            matchType ?? .iContains
        }

        /// Checks if a survey with a device type condition matches the current device type
        private func doesSurveyDeviceTypesMatch(survey: PostHogSurvey) -> Bool {
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
        private func isSurveyEventActivated(survey: PostHogSurvey) -> Bool {
            eventActivatedSurveysLock.withLock {
                eventActivatedSurveys.contains(survey.id)
            }
        }

        /// Handle a survey that is shown
        private func handleSurveyShown(survey: PostHogDisplaySurvey) {
            let activeSurvey = activeSurveyLock.withLock { self.activeSurvey }

            guard let activeSurvey, survey.id == activeSurvey.id else {
                hedgeLog("[Surveys] Received a show event for a non-active survey")
                return
            }

            sendSurveyShownEvent(survey: activeSurvey)

            // clear up event-activated surveys
            if activeSurvey.hasEvents {
                eventActivatedSurveysLock.withLock {
                    _ = eventActivatedSurveys.remove(activeSurvey.id)
                }
            }
        }

        /// Handle a survey response
        /// Processes a user's response to a survey question and determines the next question to display
        /// - Parameters:
        ///   - survey: The currently displayed survey
        ///   - index: The index of the current question being answered
        ///   - response: The user's response to the current question
        /// - Returns: The next question to display based on branching logic, or nil if there was an error
        private func handleSurveyResponse(survey: PostHogDisplaySurvey, index: Int, response: PostHogSurveyResponse) -> PostHogNextSurveyQuestion? {
            let (activeSurvey, activeSurveyQuestionIndex) = activeSurveyLock.withLock { (self.activeSurvey, self.activeSurveyQuestionIndex) }

            guard let activeSurvey, survey.id == activeSurvey.id else {
                hedgeLog("[Surveys] Received a response event for a non-active survey")
                return nil
            }

            // 2. Get next step
            let nextStep = getNextSurveyStep(
                survey: activeSurvey,
                questionIndex: activeSurveyQuestionIndex,
                response: response
            )

            let (isCompleted, nextIndex) = switch nextStep {
            case let .index(nextIndex): (false, nextIndex)
            case .end: (true, activeSurveyQuestionIndex)
            }

            let nextSurveyQuestion = PostHogNextSurveyQuestion(
                questionIndex: nextIndex,
                isSurveyCompleted: isCompleted
            )

            // update response, next question index and survey completion
            let allResponses = setActiveSurveyResponse(index: index, response: response, nextQuestion: nextSurveyQuestion)

            // send event if needed
            // TODO: Partial responses
            if isCompleted {
                sendSurveySentEvent(survey: activeSurvey, responses: allResponses)
            }

            return nextSurveyQuestion
        }

        /// Handle a survey dismiss
        private func handleSurveyClosed(survey: PostHogDisplaySurvey) {
            let (activeSurvey, activeSurveyCompleted) = activeSurveyLock.withLock { (self.activeSurvey, self.activeSurveyCompleted) }

            guard let activeSurvey, survey.id == activeSurvey.id else {
                hedgeLog("Received a close event for a non-active survey")
                return
            }

            // send survey dismissed event if needed
            if !activeSurveyCompleted {
                sendSurveyDismissedEvent(survey: activeSurvey)
            }

            // mark as seen
            setSurveySeen(survey: activeSurvey)

            // clear active survey
            clearActiveSurvey()

            // show next survey in queue, if any, after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                self.showNextSurvey()
            }
        }

        /// Sends a `survey shown` event to PostHog instance
        private func sendSurveyShownEvent(survey: PostHogSurvey) {
            sendSurveyEvent(
                event: "survey shown",
                survey: survey
            )
        }

        /// Sends a `survey sent` event to PostHog instance
        /// Sends a survey completion event to PostHog with all collected responses
        /// - Parameters:
        ///   - survey: The completed survey
        ///   - responses: Dictionary of collected responses for each question
        private func sendSurveySentEvent(survey: PostHogSurvey, responses: [String: PostHogSurveyResponse]) {
            let questionProperties: [String: Any] = [
                "$survey_questions": survey.questions.map(\.question),
                "$set": [getSurveyInteractionProperty(survey: survey, property: "responded"): true],
            ]

            // TODO: Should be doing some validation before sending the event?

            let responsesProperties: [String: Any] = responses.compactMapValues { resp in
                switch resp.type {
                case .link: resp.linkClicked == true ? "link clicked" : nil
                case .multipleChoice: resp.selectedOptions
                case .singleChoice: resp.selectedOptions?.first
                case .openEnded: resp.textValue
                case .rating: resp.ratingValue.map { "\($0)" }
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
        private func sendSurveyDismissedEvent(survey: PostHogSurvey) {
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

        private func sendSurveyEvent(event: String, survey: PostHogSurvey, additionalProperties: [String: Any] = [:]) {
            guard let postHog else {
                hedgeLog("[\(event)] event not captured, PostHog instance not found.")
                return
            }

            var properties = getBaseSurveyEventProperties(for: survey)
            properties.merge(additionalProperties) { _, new in new }

            postHog.capture(event, properties: properties)
        }

        private func getBaseSurveyEventProperties(for survey: PostHogSurvey) -> [String: Any] {
            // TODO: Add session replay screen name
            let props: [String: Any?] = [
                "$survey_name": survey.name,
                "$survey_id": survey.id,
                "$survey_iteration": survey.currentIteration,
                "$survey_iteration_start_date": survey.currentIterationStartDate.map(toISO8601String),
            ]
            return props.compactMapValues { $0 }
        }

        private func getSurveyInteractionProperty(survey: PostHogSurvey, property: String) -> String {
            var surveyProperty = "$survey_\(property)/\(survey.id)"

            if let currentIteration = survey.currentIteration, currentIteration > 0 {
                surveyProperty = "$survey_\(property)/\(survey.id)/\(currentIteration)"
            }

            return surveyProperty
        }

        private func setActiveSurvey(survey: PostHogSurvey) {
            activeSurveyLock.withLock {
                if activeSurvey == nil {
                    activeSurvey = survey
                    activeSurveyCompleted = false
                    activeSurveyResponses = [:]
                    activeSurveyQuestionIndex = 0
                }
            }
        }

        private func clearActiveSurvey() {
            activeSurveyLock.withLock {
                activeSurvey = nil
                activeSurveyCompleted = false
                activeSurveyResponses = [:]
                activeSurveyQuestionIndex = 0
            }
        }

        /// Stores a response for the current question in the active survey, and returns updated responses
        /// - Parameters:
        ///   - index: The index of the question being answered
        ///   - response: The user's response to store
        ///   - nextQuestion: The next question index and completion info
        private func setActiveSurveyResponse(
            index: Int,
            response: PostHogSurveyResponse,
            nextQuestion: PostHogNextSurveyQuestion
        ) -> [String: PostHogSurveyResponse] {
            activeSurveyLock.withLock {
                activeSurveyResponses[getResponseKey(for: index)] = response
                activeSurveyQuestionIndex = nextQuestion.questionIndex
                activeSurveyCompleted = nextQuestion.isSurveyCompleted
                return activeSurveyResponses
            }
        }

        /// Returns next question index
        /// - Parameters:
        ///   - survey: The survey which contains the question
        ///   - questionIndex: The current question index
        ///   - response: The current question response
        /// - Returns: The next question `.index()` if found, or `.end` survey reach the end
        private func getNextSurveyStep(
            survey: PostHogSurvey,
            questionIndex: Int,
            response: PostHogSurveyResponse
        ) -> NextSurveyQuestion {
            let question = survey.questions[questionIndex]
            let nextQuestionIndex = min(questionIndex + 1, survey.questions.count - 1)

            guard let branching = question.branching else {
                return questionIndex == survey.questions.count - 1 ? .end : .index(nextQuestionIndex)
            }

            switch branching {
            case .end:
                return .end

            case let .specificQuestion(index):
                return .index(min(index, survey.questions.count - 1))

            case let .responseBased(responseValues):
                return getResponseBasedNextQuestionIndex(
                    survey: survey,
                    question: question,
                    response: response,
                    responseValues: responseValues
                ) ?? .index(nextQuestionIndex)

            case .next, .unknown:
                return .index(nextQuestionIndex)
            }
        }

        /// Returns next question index based on response value (from responseValues dictionary)
        ///
        /// - Parameters:
        ///   - survey: The survey which contains the question
        ///   - question: The current question
        ///   - response: The response to the current question
        ///   - responseValues: The response values dictionary
        /// - Returns: The next index if found in the `responseValues`
        private func getResponseBasedNextQuestionIndex(
            survey: PostHogSurvey,
            question: PostHogSurveyQuestion,
            response: PostHogSurveyResponse?,
            responseValues: [String: Any]
        ) -> NextSurveyQuestion? {
            guard let response else {
                hedgeLog("[Surveys] Got response based branching, but missing the actual response.")
                return nil
            }

            switch (question, response.type) {
            case let (.singleChoice(singleChoiceQuestion), .singleChoice):
                let singleChoiceResponse = response.selectedOptions?.first
                var responseIndex = singleChoiceQuestion.choices.firstIndex(of: singleChoiceResponse ?? "")

                if responseIndex == nil, singleChoiceQuestion.hasOpenChoice == true {
                    // if the response is not found in the choices, it must be the open choice, which is always the last choice
                    responseIndex = singleChoiceQuestion.choices.count - 1
                }

                if let responseIndex, let nextIndex = responseValues["\(responseIndex)"] {
                    return processBranchingStep(nextIndex: nextIndex, totalQuestions: survey.questions.count)
                }

                hedgeLog("[Surveys] Could not find response index for specific question.")
                return nil

            case let (.rating(ratingQuestion), .rating):
                if let responseInt = response.ratingValue,
                   let ratingBucket = getRatingBucketForResponseValue(scale: ratingQuestion.scale, value: responseInt),
                   let nextIndex = responseValues[ratingBucket]
                {
                    return processBranchingStep(nextIndex: nextIndex, totalQuestions: survey.questions.count)
                }
                hedgeLog("[Surveys] Could not get response bucket for rating question.")
                return nil

            default:
                hedgeLog("[Surveys] Got response based branching for an unsupported question type.")
                return nil
            }
        }

        /// Returns next question index based on a branching step result
        /// - Parameters:
        ///   - nextIndex: The next index to process
        ///   - totalQuestions: The total number of questions in the survey
        /// - Returns: The next question index if found, or nil if not
        private func processBranchingStep(nextIndex: Any, totalQuestions: Int) -> NextSurveyQuestion? {
            if let nextIndex = nextIndex as? Int {
                return .index(min(nextIndex, totalQuestions - 1))
            }
            if let nextIndex = nextIndex as? String, nextIndex.lowercased() == "end" {
                return .end
            }
            return nil
        }

        // Gets the response bucket for a given rating response value, given the scale.
        // For example, for a scale of 3, the buckets are "negative", "neutral" and "positive".
        private func getRatingBucketForResponseValue(scale: PostHogSurveyRatingScale, value: Int) -> String? {
            // swiftlint:disable:previous cyclomatic_complexity
            // Validate input ranges
            switch scale {
            case .threePoint where RatingBucket.threePointRange.contains(value):
                switch value {
                case BucketThresholds.ThreePoint.negatives: return RatingBucket.negative
                case BucketThresholds.ThreePoint.neutrals: return RatingBucket.neutral
                default: return RatingBucket.positive
                }

            case .fivePoint where RatingBucket.fivePointRange.contains(value):
                switch value {
                case BucketThresholds.FivePoint.negatives: return RatingBucket.negative
                case BucketThresholds.FivePoint.neutrals: return RatingBucket.neutral
                default: return RatingBucket.positive
                }

            case .sevenPoint where RatingBucket.sevenPointRange.contains(value):
                switch value {
                case BucketThresholds.SevenPoint.negatives: return RatingBucket.negative
                case BucketThresholds.SevenPoint.neutrals: return RatingBucket.neutral
                default: return RatingBucket.positive
                }

            case .tenPoint where RatingBucket.tenPointRange.contains(value):
                switch value {
                case BucketThresholds.TenPoint.detractors: return RatingBucket.detractors
                case BucketThresholds.TenPoint.passives: return RatingBucket.passives
                default: return RatingBucket.promoters
                }

            default:
                hedgeLog("[Surveys] Cannot get rating bucket for invalid scale: \(scale). The scale must be one of: 3 (1-3), 5 (1-5), 7 (1-7), 10 (0-10).")
                return nil
            }
        }

        // Returns the survey response key for a specific question index
        private func getResponseKey(for index: Int) -> String {
            index == 0 ? kSurveyResponseKey : "\(kSurveyResponseKey)_\(index)"
        }

        func canShowNextSurvey() -> Bool {
            activeSurveyLock.withLock { activeSurvey == nil }
        }
    }

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
            conditions?.events?.repeatedActivation == true && hasEvents
        }
    }

    private extension PostHogSurveyMatchType {
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
            case .unknown:
                false
            }
        }
    }

    private enum RatingBucket {
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

    private enum BucketThresholds {
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

    #if TESTING
        extension PostHogSurveyMatchType {
            var matchFunction: (_ targets: [String], _ value: String) -> Bool {
                matches
            }
        }

        extension PostHogSurveyIntegration {
            func setSurveys(_ surveys: [PostHogSurvey]) {
                allSurveys = surveys
            }

            func setShownSurvey(_ survey: PostHogSurvey) {
                clearActiveSurvey()
                setActiveSurvey(survey: survey)
            }

            func getNextQuestion(index: Int, response: PostHogSurveyResponse) -> (Int, Bool)? {
                guard let activeSurvey else { return nil }
                activeSurveyQuestionIndex = index
                if let next = handleSurveyResponse(survey: activeSurvey.toDisplaySurvey(), index: index, response: response) {
                    return (next.questionIndex, next.isSurveyCompleted)
                }
                return nil
            }

            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
            }
        }
    #endif
#endif
