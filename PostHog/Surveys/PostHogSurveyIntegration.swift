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
        var requiresSwizzling: Bool { true }

        private static let integrationInstallState = PostHogIntegrationInstallState()

        typealias SurveyCallback = (_ surveys: [PostHogSurvey]) -> Void

        private let kSurveySeenKeyPrefix = "seenSurvey_"
        private let kSurveyResponseKey = "$survey_response"

        var postHog: PostHogSDK?
        private var config: PostHogConfig? { postHog?.config }
        private var storage: PostHogStorage? { postHog?.storage }
        private var remoteConfig: PostHogRemoteConfig? { postHog?.remoteConfig }

        private var allSurveysLock = NSLock()
        private var allSurveys: [PostHogSurvey]?

        private var eventsToSurveysLock = NSLock()
        private var eventsToSurveys: [String: [(surveyId: String, condition: PostHogEventCondition)]] = [:]

        let eventActivatedSurveysLock = NSLock()
        var eventActivatedSurveys: [String: [PostHogEventCondition]] = [:]
        let freshFeatureFlagsLock = NSLock()
        let surveyRefreshProcessingLock = NSLock()
        var surveyRefreshGeneration = 0
        var surveyAwaitingFeatureFlagsGeneration: Int?
        var surveyFeatureFlagsUnavailable = false
        #if os(iOS)
            var hasActiveSurveyWindow: () -> Bool = { UIApplication.getCurrentWindow() != nil }
        #endif

        private var didBecomeActiveToken: RegistrationToken?
        private var didLayoutViewToken: RegistrationToken?
        private var eventCapturedToken: RegistrationToken?
        private var personPropertiesChangedToken: RegistrationToken?
        var remoteConfigLoadedToken: RegistrationToken?
        var featureFlagsLoadedToken: RegistrationToken?

        private var activeSurveyLock = NSLock()
        private var activeSurvey: PostHogSurvey?
        private var activeSurveyAttemptId: UUID?
        private var activeSurveyGeneration: String?
        private var progressStore: SurveyProgressStore?
        private var activeProgressWasPersisted = false
        private var activeSurveySubmissionId: String?
        private var activeSurveyLanguage: String?
        /// Language the survey was rendered with, frozen at show time and reused as `$survey_language` on
        /// `sent`/`dismissed`. Not touched by `refreshActiveSurveyTranslations`, so a drop stays detectable.
        private var activeSurveyRenderedLanguage: String?
        private var activeSurveyQuestionTranslations: [PostHogSurveyQuestionTranslation?]?
        /// Question translations frozen at show time — the fallback text for questions never answered,
        /// keeping them in `$survey_language` rather than a later live re-translation.
        private var activeSurveyRenderedQuestionTranslations: [PostHogSurveyQuestionTranslation?]?
        private var activeSurveyResponses: [String: PostHogSurveyResponse] = [:] // keyed by question identifier
        private var activeSurveyResponseLanguage: String?
        /// Question text as shown when each question was answered, keyed like `activeSurveyResponses`, so
        /// a later re-translation can't rewrite the language a question was answered in.
        private var activeSurveyResponseQuestionText: [String: String] = [:]
        private var activeSurveyCompleted: Bool = false
        private var activeSurveyQuestionIndex: Int = 0

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            installIfNeeded(using: Self.integrationInstallState) {
                self.postHog = postHog
                if let storage = postHog.storage { progressStore = SurveyProgressStore(storage: storage) }
                start()
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            uninstallIfNeeded(from: postHog, installedPostHog: self.postHog, state: Self.integrationInstallState) {
                stop()
                self.postHog = nil
            }
        }

        func start() {
            // Re-resolve a shown survey's language when the person properties used for flags change. Not
            // gated on `os(iOS)` so resolution stays exercised under TESTING; the UI update no-ops off iOS.
            personPropertiesChangedToken = postHog?.remoteConfig?.onPersonPropertiesForFlagsChanged.subscribe { [weak self] _ in
                self?.refreshActiveSurveyTranslations()
            }
            subscribeToRemoteConfigUpdates()
            #if os(iOS)
                // Subscribe to event captures
                eventCapturedToken = postHog?.onEventCaptured.subscribe { [weak self] event in
                    self?.onEvent(event: event)
                }
                // TODO: listen to screen view events
                didLayoutViewToken = DI.main.viewLayoutPublisher.onViewLayout.subscribe(throttle: 5) { [weak self] in
                    self?.showNextSurvey()
                }
                didBecomeActiveToken = DI.main.appLifecyclePublisher.onDidBecomeActive.subscribe { [weak self] in
                    self?.showNextSurvey()
                }
            #endif
        }

        func stop() {
            eventCapturedToken = nil
            didBecomeActiveToken = nil
            didLayoutViewToken = nil
            personPropertiesChangedToken = nil
            clearActiveSurvey()
            unsubscribeFromRemoteConfigUpdates()
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
                        self.hasProgress($0) || !self.getSurveySeen(survey: $0)
                    }
                    .filter(\.isActive) // 2. that are active,
                    .filter { survey in // 3. and match display conditions,
                        // TODO: Check screen conditions
                        // TODO: Check event conditions
                        self.doesSurveyDeviceTypesMatch(survey: survey) &&
                            // web-only conditions (CSS selector / URL) can never be satisfied natively
                            !self.hasWebOnlyConditions(survey: survey)
                    }
                    .filter { survey in // 3.5. wait period has passed
                        self.hasWaitPeriodPassed(survey: survey)
                    }
                    .filter { survey in // 4. and match linked flags
                        let allKeys: [String?] = [
                            [survey.linkedFlagKey],
                            [survey.targetingFlagKey],
                            // we check internal targeting flags only if this survey cannot be activated repeatedly
                            [survey.canActivateRepeatedly || self.hasProgress(survey) ? nil : survey.internalTargetingFlagKey],
                            survey.featureFlagKeys?.compactMap { kvp in
                                kvp.key.isEmpty ? nil : kvp.value
                            } ?? [],
                        ]
                        .joined()
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }

                        guard allKeys.isEmpty || self.canEvaluateSurveyFeatureFlags else { return false }
                        // all keys must be enabled
                        return Set(allKeys)
                            .allSatisfy(self.isSurveyFeatureFlagEnabled)
                    }
                    .filter { survey in // 5. and if event-based, have been activated by that event
                        survey.hasEvents ? self.isSurveyEventActivated(survey: survey) : true
                    }

                callback(Array(matchingSurveys).sorted { self.hasProgress($0) && !self.hasProgress($1) })
            }
        }

        private func onEvent(event: PostHogEvent) {
            let candidates = eventsToSurveysLock.withLock { eventsToSurveys[event.event] } ?? []
            guard !candidates.isEmpty else { return }

            let matchingSurveys = candidates
                .filter { matchPropertyFilters($0.condition.propertyFilters, eventProperties: event.properties) }

            guard !matchingSurveys.isEmpty else { return }

            eventActivatedSurveysLock.withLock {
                for survey in matchingSurveys where eventActivatedSurveys[survey.surveyId]?.contains(survey.condition) != true {
                    eventActivatedSurveys[survey.surveyId, default: []].append(survey.condition)
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
            getCachedOrReload(
                getCached: remoteConfig.getRemoteConfig,
                reload: { remoteConfig.reloadRemoteConfig(callback: $0) },
                forceReload: forceReload,
                callback: callback
            )
        }

        private func getFeatureFlags(
            _ remoteConfig: PostHogRemoteConfig,
            forceReload: Bool = false,
            callback: (([String: Any]?) -> Void)? = nil
        ) {
            getCachedOrReload(
                getCached: remoteConfig.getFeatureFlags,
                reload: { remoteConfig.reloadFeatureFlags(callback: $0) },
                forceReload: forceReload,
                callback: callback
            )
        }

        private func getCachedOrReload(
            getCached: () -> [String: Any]?,
            reload: ((([String: Any]?) -> Void)?) -> Void,
            forceReload: Bool,
            callback: (([String: Any]?) -> Void)?
        ) {
            let cached = getCached()
            if cached == nil || forceReload {
                reload(callback)
            } else {
                callback?(cached)
            }
        }

        func updateSurveyCache(
            _ surveys: [PostHogSurvey],
            events: [String: [(surveyId: String, condition: PostHogEventCondition)]]
        ) {
            allSurveysLock.withLock { allSurveys = surveys }
            eventsToSurveysLock.withLock { eventsToSurveys = events }
            reconcileEventActivations(with: surveys)
            progressStore?.reconcile(surveys)
        }

        private func isSurveyFeatureFlagEnabled(flagKey: String?) -> Bool {
            guard let flagKey, let postHog else {
                return false
            }

            return postHog.isFeatureEnabled(flagKey)
        }

        /// Shows next survey in queue. No-op if a survey is already being shown
        func showNextSurvey() {
            #if os(iOS)
                guard #available(iOS 15.0, *) else {
                    hedgeLog("[Surveys] Surveys can be rendered only on iOS 15+")
                    return
                }

                guard Thread.isMainThread else {
                    DispatchQueue.main.async { [weak self] in self?.showNextSurvey() }
                    return
                }
                guard hasActiveSurveyWindow(), canShowNextSurvey() else { return }

                let refreshGeneration = freshFeatureFlagsLock.withLock { surveyRefreshGeneration }
                getActiveMatchingSurveys { activeSurveys in
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.freshFeatureFlagsLock.withLock({ self.surveyRefreshGeneration == refreshGeneration }),
                              self.hasActiveSurveyWindow(),
                              self.canShowNextSurvey(),
                              let survey = activeSurveys.first(where: self.canRenderSurvey)
                        else { return }

                        let language = self.resolveDisplayLanguage()
                        let translations = resolveSurveyTranslations(survey: survey, targetLanguage: language)
                        self.setActiveSurvey(survey: survey, language: translations.matchedKey, questionTranslations: translations.questions)

                        let callbacks = self.makeSurveyCallbacks()
                        // render the survey
                        self.postHog?.config.surveysConfig.surveysDelegate.renderSurvey(
                            survey.toDisplaySurvey(
                                surveyTranslation: translations.survey,
                                questionTranslations: translations.questions,
                                initialQuestionIndex: self.activeSurveyLock.withLock { self.activeSurveyQuestionIndex }
                            ),
                            onSurveyShown: callbacks.shown,
                            onSurveyResponse: callbacks.response,
                            onSurveyClosed: callbacks.closed
                        )
                    }
                }
            #endif
        }

        /// Re-resolves the on-screen survey's language and, if it changed, pushes the freshly
        /// translated content to the delegate for an in-place update. No-op when the delegate has no
        /// `updateSurvey`, no survey is active, or the language is unchanged (so it never re-stamps
        /// `$survey_language` or re-renders when nothing visible would change).
        private func refreshActiveSurveyTranslations() {
            // `updateSurvey` is optional; without it, skip so the tracked language never advances past
            // what's actually on screen.
            guard #available(iOS 15.0, *),
                  let updateSurvey = postHog?.config._surveysConfig.surveysDelegate.updateSurvey
            else { return }

            // Enqueue the update inside `activeSurveyLock` so main-queue order matches commit order:
            // racing refreshes can't leave the survey in a language other than `activeSurveyLanguage`.
            activeSurveyLock.withLock {
                guard let activeSurvey = self.activeSurvey else { return }

                let language = resolveDisplayLanguage()
                let translations = resolveSurveyTranslations(survey: activeSurvey, targetLanguage: language)

                // Commit only if the update targets a different language than what's currently shown
                guard self.activeSurveyLanguage != translations.matchedKey else { return }
                self.activeSurveyLanguage = translations.matchedKey
                self.activeSurveyQuestionTranslations = translations.questions

                let displaySurvey = activeSurvey.toDisplaySurvey(
                    surveyTranslation: translations.survey,
                    questionTranslations: translations.questions
                )

                DispatchQueue.main.async {
                    updateSurvey(displaySurvey)
                }
            }
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
            return surveysSeen[key] as? Bool ?? false
        }

        /// Mark a survey as seen
        private func setSurveySeen(survey: PostHogSurvey, generation: String? = nil) {
            storage?.withSurveyState { currentGeneration in
                guard generation == nil || generation == currentGeneration else { return }
                var seenKeys = storage?.getDictionary(forKey: .surveySeen) ?? [:]
                seenKeys[getSurveySeenKey(survey)] = true
                storage?.setDictionary(forKey: .surveySeen, contents: seenKeys)
                setLastSeenSurveyDate(Date())
            }
        }

        /// Returns the current survey seen list from disk, including changes made by reset.
        private func getSeenSurveyKeys() -> [AnyHashable: Any] {
            storage?.withSurveyState { _ in storage?.getDictionary(forKey: .surveySeen) ?? [:] } ?? [:]
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

        /// Checks if a survey is scoped to web-only display conditions (CSS selector or URL).
        ///
        /// These conditions can only be evaluated in a web context, so a survey that carries them
        /// should never display in a native app. This keeps web-only surveys from leaking onto iOS
        /// when the same survey is enabled across both surfaces.
        private func hasWebOnlyConditions(survey: PostHogSurvey) -> Bool {
            guard let conditions = survey.conditions else {
                return false
            }

            let hasSelector = !(conditions.selector?.isEmpty ?? true)
            let hasUrl = !(conditions.url?.isEmpty ?? true)

            return hasSelector || hasUrl
        }

        /// Checks if the wait period has passed since the last seen survey date
        private func hasWaitPeriodPassed(survey: PostHogSurvey) -> Bool {
            guard let waitPeriodInDays = survey.conditions?.seenSurveyWaitPeriodInDays else {
                return true
            }
            guard let lastSeenDate = getLastSeenSurveyDate() else {
                return true
            }
            let now = Date()
            let diffSeconds = abs(now.timeIntervalSince(lastSeenDate))
            let diffDays = Int(ceil(diffSeconds / secondsPerDay))
            return diffDays > waitPeriodInDays
        }

        private func getLastSeenSurveyDate() -> Date? {
            guard let dateString = storage?.getString(forKey: .lastSeenSurveyDate) else { return nil }
            return toISO8601Date(dateString)
        }

        private func setLastSeenSurveyDate(_ date: Date) {
            storage?.setString(forKey: .lastSeenSurveyDate, contents: toISO8601String(date))
        }

        /// Checks if the given event properties satisfy all property filters.
        /// Returns true if propertyFilters is nil or empty (no filters = match all).
        private func matchPropertyFilters(
            _ propertyFilters: [String: PostHogPropertyFilter]?,
            eventProperties: [String: Any]
        ) -> Bool {
            guard let propertyFilters, !propertyFilters.isEmpty else {
                return true
            }
            return propertyFilters.allSatisfy { propertyName, filter in
                guard let eventValue = eventProperties[propertyName] else {
                    return false
                }
                let eventValueString = String(describing: eventValue)
                return filter.matchOperator.matches(targets: filter.values, value: eventValueString)
            }
        }

        /// Checks if a survey has been previously activated by an associated event
        private func isSurveyEventActivated(survey: PostHogSurvey) -> Bool {
            let activatedConditions = eventActivatedSurveysLock.withLock { eventActivatedSurveys[survey.id] } ?? []
            let currentConditions = survey.conditions?.events?.values ?? []
            return activatedConditions.contains { currentConditions.contains($0) }
        }

        private func makeSurveyCallbacks() -> SurveyCallbacks {
            let attemptId = activeSurveyLock.withLock { activeSurveyAttemptId }
            return SurveyCallbacks(
                shown: { [weak self] in self?.handleSurveyShown(survey: $0, attemptId: attemptId) },
                response: { [weak self] in self?.handleSurveyResponse(survey: $0, index: $1, response: $2, attemptId: attemptId) },
                closed: { [weak self] in self?.handleSurveyClosed(survey: $0, attemptId: attemptId) }
            )
        }

        private func withActiveSurveyAttempt<T>(_ attemptId: UUID?, _ operation: (String) -> T?) -> T? {
            activeSurveyLock.withLock {
                guard let attemptId, attemptId == activeSurveyAttemptId, let storage else { return nil }
                return storage.withSurveyState { generation in
                    guard activeSurveyGeneration == generation else {
                        clearActiveSurveyLocked()
                        return nil
                    }
                    let result = operation(generation)
                    guard storage.isSurveyGenerationCurrent(generation) else {
                        clearActiveSurveyLocked()
                        return nil
                    }
                    return result
                }
            }
        }

        /// Handle a survey that is shown
        private func handleSurveyShown(survey: PostHogDisplaySurvey, attemptId: UUID?) {
            let shown: (survey: PostHogSurvey, generation: String)? = withActiveSurveyAttempt(attemptId) { generation in
                guard let activeSurvey, survey.id == activeSurvey.id else {
                    hedgeLog("[Surveys] Received a show event for a non-active survey")
                    return nil
                }
                // clear up event-activated surveys
                if activeSurvey.hasEvents {
                    eventActivatedSurveysLock.withLock { _ = eventActivatedSurveys.removeValue(forKey: activeSurvey.id) }
                }
                return (activeSurvey, generation)
            }
            guard let shown else { return }
            reconcileRenderedTranslationOnShow(activeSurvey: shown.survey, attemptId: attemptId)
            // Read after the reconcile so the shown event reports the reconciled language.
            let language = activeSurveyLock.withLock { self.activeSurveyLanguage }
            sendSurveyShownEvent(survey: shown.survey, language: language, generation: shown.generation)
        }

        /// Re-delivers the current translation for a language change that committed after `setActiveSurvey`
        /// but before the survey was on screen — a window where `updateSurvey` is dropped and later
        /// refreshes no-op. Pushes one update to catch up.
        private func reconcileRenderedTranslationOnShow(activeSurvey: PostHogSurvey, attemptId: UUID?) {
            guard #available(iOS 15.0, *),
                  let updateSurvey = postHog?.config._surveysConfig.surveysDelegate.updateSurvey
            else { return }

            activeSurveyLock.withLock {
                guard attemptId == activeSurveyAttemptId, activeSurveyRenderedLanguage != activeSurveyLanguage else { return }

                let language = resolveDisplayLanguage()
                let translations = resolveSurveyTranslations(survey: activeSurvey, targetLanguage: language)
                activeSurveyLanguage = translations.matchedKey
                activeSurveyQuestionTranslations = translations.questions
                activeSurveyRenderedLanguage = translations.matchedKey
                activeSurveyRenderedQuestionTranslations = translations.questions

                let displaySurvey = activeSurvey.toDisplaySurvey(
                    surveyTranslation: translations.survey,
                    questionTranslations: translations.questions
                )

                DispatchQueue.main.async {
                    updateSurvey(displaySurvey)
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
        private func handleSurveyResponse(
            survey: PostHogDisplaySurvey, index: Int, response: PostHogSurveyResponse, attemptId: UUID?
        ) -> PostHogNextSurveyQuestion? {
            let result: (next: PostHogNextSurveyQuestion, capture: () -> Void)? = withActiveSurveyAttempt(attemptId) { generation in
                let (activeSurvey, activeSurveyQuestionIndex, shownLanguage, renderedQuestionTranslations, submissionId) =
                    (self.activeSurvey, self.activeSurveyQuestionIndex, self.activeSurveyRenderedLanguage,
                     self.activeSurveyRenderedQuestionTranslations, self.activeSurveySubmissionId)

                guard let activeSurvey, survey.id == activeSurvey.id else {
                    hedgeLog("[Surveys] Received a response event for a non-active survey")
                    return nil
                }

                guard !activeProgressWasPersisted || progressStore?.load(activeSurvey)?.submissionId == submissionId else {
                    clearActiveSurveyLocked()
                    return nil
                }

                guard !activeSurveyCompleted, index >= 0, index == activeSurveyQuestionIndex, activeSurvey.questions.indices.contains(index) else { return nil }

                // TODO: ideally the handleSurveyResponse should pass the question ID as param but it would break the Flutter SDK for older versions
                let questionId: String
                if index < survey.questions.count {
                    let question = survey.questions[index]
                    questionId = question.id
                } else {
                    // this should not happen, its only for back compatibility
                    questionId = ""
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

                let stored = setActiveSurveyResponseLocked(id: questionId, index: index, response: response, nextQuestion: nextSurveyQuestion)

                return (nextSurveyQuestion, { [weak self] in
                    // send event if needed
                    if activeSurvey.enablePartialResponses == true || isCompleted {
                        self?.sendSurveySentEvent(
                            survey: activeSurvey, responses: stored.responses, submissionId: submissionId,
                            isCompleted: isCompleted, language: shownLanguage,
                            questionTranslations: renderedQuestionTranslations, responseQuestionText: stored.questionText,
                            generation: generation
                        )
                    }
                })
            }
            result?.capture()
            return result?.next
        }

        /// Handle a survey dismiss
        private func handleSurveyClosed(survey: PostHogDisplaySurvey, attemptId: UUID?) {
            let capture: (() -> Void)? = withActiveSurveyAttempt(attemptId) { generation in
                let activeSurvey = self.activeSurvey
                let completed = activeSurveyCompleted
                let responses = activeSurveyResponses
                let language = responses.isEmpty ? activeSurveyRenderedLanguage : activeSurveyResponseLanguage
                let translations = activeSurveyRenderedQuestionTranslations
                let questionText = activeSurveyResponseQuestionText
                let submissionId = activeSurveySubmissionId

                guard let activeSurvey, survey.id == activeSurvey.id else {
                    hedgeLog("Received a close event for a non-active survey")
                    return nil
                }

                guard activeSurveyCompleted || !activeProgressWasPersisted || progressStore?.load(activeSurvey)?.submissionId == submissionId else {
                    clearActiveSurveyLocked()
                    return nil
                }

                progressStore?.remove(activeSurvey)
                setSurveySeen(survey: activeSurvey, generation: generation)
                clearActiveSurveyLocked()
                return { [weak self] in
                    if !completed {
                        self?.sendSurveyDismissedEvent(
                            survey: activeSurvey, responses: responses, submissionId: submissionId,
                            language: language, questionTranslations: translations,
                            responseQuestionText: questionText, generation: generation
                        )
                    }
                }
            }
            guard let capture else { return }
            capture()
            // show next survey in queue, if any, after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in self?.showNextSurvey() }
        }

        /// Sends a `survey shown` event to PostHog instance
        private func sendSurveyShownEvent(survey: PostHogSurvey, language: String? = nil, generation: String? = nil) {
            sendSurveyEvent(
                event: "survey shown",
                survey: survey,
                language: language,
                generation: generation
            )
        }

        /// Sends a `survey sent` event to PostHog instance
        /// Sends a survey completion event to PostHog with all collected responses
        /// - Parameters:
        ///   - survey: The completed survey
        ///   - responses: Dictionary of collected responses for each question
        private func sendSurveySentEvent(
            survey: PostHogSurvey,
            responses: [String: PostHogSurveyResponse],
            submissionId: String? = nil,
            isCompleted: Bool = true,
            language: String? = nil,
            questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil,
            responseQuestionText: [String: String] = [:],
            generation: String? = nil
        ) {
            var additionalProperties = buildSurveyResponseProperties(
                survey: survey,
                responses: responses,
                questionTranslations: questionTranslations,
                responseQuestionText: responseQuestionText
            ).merging(
                [
                    "$survey_completed": isCompleted,
                    "$set": [survey.interactionProperty("responded"): true],
                ],
                uniquingKeysWith: { _, new in new }
            )

            additionalProperties["$survey_submission_id"] = submissionId
            setSurveySeen(survey: survey, generation: generation)
            sendSurveyEvent(
                event: "survey sent",
                survey: survey,
                additionalProperties: additionalProperties,
                language: language,
                generation: generation
            )
        }

        /// Sends a `survey dismissed` event to PostHog instance
        private func sendSurveyDismissedEvent(
            survey: PostHogSurvey,
            responses: [String: PostHogSurveyResponse],
            submissionId: String? = nil,
            language: String? = nil,
            questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil,
            responseQuestionText: [String: String] = [:],
            generation: String? = nil
        ) {
            var additionalProperties = buildSurveyResponseProperties(
                survey: survey,
                responses: responses,
                questionTranslations: questionTranslations,
                responseQuestionText: responseQuestionText
            ).merging(
                [
                    "$survey_partially_completed": surveyHasResponses(responses),
                    "$set": [
                        survey.interactionProperty("dismissed"): true,
                    ],
                ],
                uniquingKeysWith: { _, new in new }
            )

            additionalProperties["$survey_submission_id"] = submissionId
            sendSurveyEvent(
                event: "survey dismissed",
                survey: survey,
                additionalProperties: additionalProperties,
                language: language,
                generation: generation
            )
        }

        private func buildSurveyResponseProperties(
            survey: PostHogSurvey,
            responses: [String: PostHogSurveyResponse],
            questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil,
            responseQuestionText: [String: String] = [:]
        ) -> [String: Any] {
            let responsesProperties: [String: Any] = responses.compactMapValues { getSurveyResponseValue(for: $0) }

            let surveyQuestions = survey.questions.enumerated().map { index, question in
                let key = responseKey(questionId: question.id, index: index)
                // Report the text the user saw: answer-time snapshot, else show-time translation, else base.
                let effectiveQuestion = responseQuestionText[key]
                    ?? translatedQuestionText(from: questionTranslations, at: index)
                    ?? question.question
                var questionData: [String: Any] = [
                    "id": question.id,
                    "question": effectiveQuestion,
                ]

                if let response = responsesProperties[key] {
                    questionData["response"] = response
                }

                return questionData
            }

            return ["$survey_questions": surveyQuestions].merging(responsesProperties, uniquingKeysWith: { _, new in new })
        }

        private func surveyHasResponses(_ responses: [String: PostHogSurveyResponse]) -> Bool {
            responses.values.contains { getSurveyResponseValue(for: $0) != nil }
        }

        private func getSurveyResponseValue(for response: PostHogSurveyResponse) -> Any? {
            switch response.type {
            case .link: response.linkClicked == true ? "link clicked" : nil
            case .multipleChoice: response.selectedOptions
            case .singleChoice: response.selectedOptions?.first
            case .openEnded: response.textValue
            case .rating: response.ratingValue.map { "\($0)" }
            }
        }

        private func sendSurveyEvent(
            event: String, survey: PostHogSurvey, additionalProperties: [String: Any] = [:], language: String? = nil, generation: String? = nil
        ) {
            guard let postHog else {
                hedgeLog("[\(event)] event not captured, PostHog instance not found.")
                return
            }

            var properties = survey.eventProperties
            properties.merge(additionalProperties) { _, new in new }
            if let language, !language.isEmpty {
                properties["$survey_language"] = language
            }

            guard let distinctId = postHog.surveyEventDistinctId(generation: generation) else { return }
            // Keep user hooks outside the state locks: a hook may reset or start another survey.
            postHog.capture(event, distinctId: distinctId, properties: properties)
        }

        private func setActiveSurvey(survey: PostHogSurvey, language: String? = nil, questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil) {
            activeSurveyLock.withLock {
                guard let storage else { return }
                storage.withSurveyState { generation in
                    if activeSurvey == nil {
                        let progress = progressStore?.load(survey) ?? SurveyProgress(
                            resetEpoch: generation, submissionId: UUID().uuidString,
                            questionOrder: SurveyProgress.questionOrder(for: survey)
                        )
                        guard storage.isSurveyGenerationCurrent(generation) else { return }
                        activeSurvey = survey
                        activeSurveyAttemptId = UUID()
                        activeSurveyGeneration = generation
                        activeSurveySubmissionId = progress.submissionId
                        activeSurveyLanguage = language
                        activeSurveyRenderedLanguage = language
                        activeSurveyQuestionTranslations = questionTranslations
                        activeSurveyRenderedQuestionTranslations = questionTranslations
                        activeSurveyCompleted = false
                        activeSurveyResponses = progress.responses.compactMapValues { $0.response }
                        activeSurveyResponseQuestionText = progress.questionText
                        activeSurveyResponseLanguage = progress.language
                        activeSurveyQuestionIndex = progress.questionIndex
                        activeProgressWasPersisted = progressStore?.load(survey) != nil
                    }
                }
            }
        }

        private func hasProgress(_ survey: PostHogSurvey) -> Bool {
            progressStore?.load(survey) != nil
        }

        private func persistActiveProgressLocked() {
            guard let survey = activeSurvey, let submissionId = activeSurveySubmissionId, let resetEpoch = activeSurveyGeneration else { return }
            if activeSurveyCompleted {
                progressStore?.remove(survey)
                return
            }
            var progress = SurveyProgress(resetEpoch: resetEpoch, submissionId: submissionId, questionOrder: SurveyProgress.questionOrder(for: survey))
            progress.questionIndex = activeSurveyQuestionIndex
            progress.responses = activeSurveyResponses.mapValues(StoredSurveyResponse.init)
            progress.questionText = activeSurveyResponseQuestionText
            progress.language = activeSurveyResponseLanguage
            progressStore?.save(progress, for: survey)
            activeProgressWasPersisted = progressStore?.load(survey) != nil
        }

        private func clearActiveSurvey() {
            activeSurveyLock.withLock { clearActiveSurveyLocked() }
        }

        private func clearActiveSurveyLocked() {
            activeSurvey = nil
            activeSurveyAttemptId = nil
            activeSurveyGeneration = nil
            activeSurveySubmissionId = nil
            activeProgressWasPersisted = false
            activeSurveyLanguage = nil
            activeSurveyRenderedLanguage = nil
            activeSurveyQuestionTranslations = nil
            activeSurveyRenderedQuestionTranslations = nil
            activeSurveyCompleted = false
            activeSurveyResponses = [:]
            activeSurveyResponseQuestionText = [:]
            activeSurveyResponseLanguage = nil
            activeSurveyQuestionIndex = 0
        }

        private func resolveDisplayLanguage() -> String? {
            // `surveysConfig` is `@available(macOS, unavailable)`, but this integration is
            // also compiled for non-iOS targets under TESTING. Read the backing property
            // directly so the file stays compilable on every platform.
            let override = config?._surveysConfig.overrideDisplayLanguage
            let personProperties = remoteConfig?.getPersonPropertiesForFlags()
            let rawLocale = Locale.current.identifier
            let deviceLocale = rawLocale.replacingOccurrences(of: "_", with: "-")
            return detectSurveyLanguage(
                overrideLanguage: override,
                personProperties: personProperties,
                deviceLocale: deviceLocale
            )
        }

        /// Stores a response for the current question, returning the updated responses and the
        /// per-question displayed-text snapshot.
        /// - Parameters:
        ///   - id: The question ID, empty if none
        ///   - index: The index of the question being answered
        ///   - response: The user's response to store
        ///   - nextQuestion: The next question index and completion info
        private func setActiveSurveyResponseLocked(
            id: String,
            index: Int,
            response: PostHogSurveyResponse,
            nextQuestion: PostHogNextSurveyQuestion
        ) -> (responses: [String: PostHogSurveyResponse], questionText: [String: String]) {
            let displayedText = displayedQuestionTextLocked(at: index)

            // Response is stored under both key formats for back compatibility; the snapshot only
            // needs the single key it's read back under.
            activeSurveyResponses[getOldResponseKey(for: index)] = response
            if !id.isEmpty {
                activeSurveyResponses[getNewResponseKey(for: id)] = response
            }
            activeSurveyResponseQuestionText[responseKey(questionId: id, index: index)] = displayedText
            activeSurveyResponseLanguage = activeSurveyRenderedLanguage
            activeSurveyQuestionIndex = nextQuestion.questionIndex
            activeSurveyCompleted = nextQuestion.isSurveyCompleted
            persistActiveProgressLocked()
            return (activeSurveyResponses, activeSurveyResponseQuestionText)
        }

        /// The response-property key for a question, matching the one used when storing its response.
        private func responseKey(questionId: String, index: Int) -> String {
            questionId.isEmpty ? getOldResponseKey(for: index) : getNewResponseKey(for: questionId)
        }

        private func translatedQuestionText(from translations: [PostHogSurveyQuestionTranslation?]?, at index: Int) -> String? {
            guard let translations, translations.indices.contains(index) else { return nil }
            return translations[index]?.question
        }

        /// Text on screen for `index`: the applied translation, else the base text; `nil` if out of range.
        /// Must be called with `activeSurveyLock` held.
        private func displayedQuestionTextLocked(at index: Int) -> String? {
            if let translated = translatedQuestionText(from: activeSurveyQuestionTranslations, at: index) {
                return translated
            }
            guard let questions = activeSurvey?.questions, questions.indices.contains(index) else {
                return nil
            }
            return questions[index].question
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

        // Returns the old survey response key for a specific question index
        private func getOldResponseKey(for index: Int) -> String {
            index == 0 ? kSurveyResponseKey : "\(kSurveyResponseKey)_\(index)"
        }

        // Returns the new survey response key for a specific question id
        private func getNewResponseKey(for questionId: String) -> String {
            "\(kSurveyResponseKey)_\(questionId)"
        }

        func canShowNextSurvey() -> Bool {
            activeSurveyLock.withLock { activeSurvey == nil }
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

            func setShownSurvey(_ survey: PostHogSurvey, language: String? = nil, questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil) {
                clearActiveSurvey()
                setActiveSurvey(survey: survey, language: language, questionTranslations: questionTranslations)
            }

            func testSurveyCallbacks() -> SurveyCallbacks {
                makeSurveyCallbacks()
            }

            var testActiveQuestionIndex: Int { activeSurveyLock.withLock { activeSurveyQuestionIndex } }
            var testActiveSubmissionId: String? { activeSurveyLock.withLock { activeSurveySubmissionId } }

            var testActiveSurveyLanguage: String? {
                activeSurveyLock.withLock { self.activeSurveyLanguage }
            }

            func testRefreshActiveSurveyTranslations() {
                refreshActiveSurveyTranslations()
            }

            func getNextQuestion(index: Int, response: PostHogSurveyResponse) -> (Int, Bool)? {
                guard let activeSurvey else { return nil }
                activeSurveyQuestionIndex = index
                if let next = makeSurveyCallbacks().response(activeSurvey.toDisplaySurvey(), index, response) {
                    return (next.questionIndex, next.isSurveyCompleted)
                }
                return nil
            }

            func testSendSurveyShownEvent(survey: PostHogSurvey, language: String? = nil) {
                sendSurveyShownEvent(survey: survey, language: language)
            }

            func testHandleSurveyShown(survey: PostHogDisplaySurvey) {
                makeSurveyCallbacks().shown(survey)
            }

            func testHandleSurveyClosed(survey: PostHogDisplaySurvey) {
                makeSurveyCallbacks().closed(survey)
            }

            func testSendSurveySentEvent(
                survey: PostHogSurvey,
                responses: [String: PostHogSurveyResponse],
                language: String? = nil,
                questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil,
                responseQuestionText: [String: String] = [:]
            ) {
                sendSurveySentEvent(
                    survey: survey,
                    responses: responses,
                    language: language,
                    questionTranslations: questionTranslations,
                    responseQuestionText: responseQuestionText
                )
            }

            func testSendSurveyDismissedEvent(
                survey: PostHogSurvey,
                responses: [String: PostHogSurveyResponse] = [:],
                language: String? = nil,
                questionTranslations: [PostHogSurveyQuestionTranslation?]? = nil,
                responseQuestionText: [String: String] = [:]
            ) {
                sendSurveyDismissedEvent(
                    survey: survey,
                    responses: responses,
                    language: language,
                    questionTranslations: questionTranslations,
                    responseQuestionText: responseQuestionText
                )
            }

            func testGetBaseSurveyEventProperties(for survey: PostHogSurvey) -> [String: Any] {
                survey.eventProperties
            }

            func testGetSurveyInteractionProperty(survey: PostHogSurvey, property: String) -> String {
                survey.interactionProperty(property)
            }

            func testGetResponseKey(questionId: String) -> String {
                getNewResponseKey(for: questionId)
            }

            func testMatchPropertyFilters(
                _ propertyFilters: [String: PostHogPropertyFilter]?,
                eventProperties: [String: Any]
            ) -> Bool {
                matchPropertyFilters(propertyFilters, eventProperties: eventProperties)
            }

            func testSetEventsToSurveys(_ map: [String: [(surveyId: String, condition: PostHogEventCondition)]]) {
                eventsToSurveysLock.withLock {
                    eventsToSurveys = map
                }
            }

            func testIsEventActivated(surveyId: String) -> Bool {
                eventActivatedSurveysLock.withLock {
                    eventActivatedSurveys[surveyId] != nil
                }
            }

            func testOnEvent(event: PostHogEvent) {
                onEvent(event: event)
            }

            static func clearInstalls() {
                integrationInstallState.clear()
            }
        }
    #endif
#endif
