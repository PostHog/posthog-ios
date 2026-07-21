//
//  PostHogSurveyTranslationsTest.swift
//  PostHog
//
//  Created by PostHog Code on 2026-05-13.
//

#if os(iOS) || TESTING

    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Test survey translations")
    enum PostHogSurveyTranslationsTest {
        @Suite("Test language detection")
        struct TestLanguageDetection {
            @Test("override wins over person property and locale")
            func overrideWinsOverPersonPropertyAndLocale() {
                let result = detectSurveyLanguage(
                    overrideLanguage: "fr",
                    personProperties: ["language": "de"],
                    deviceLocale: "en-US"
                )
                #expect(result == "fr")
            }

            @Test("trims override whitespace")
            func trimsOverride() {
                let result = detectSurveyLanguage(
                    overrideLanguage: "  pt-BR  ",
                    personProperties: nil,
                    deviceLocale: "en-US"
                )
                #expect(result == "pt-BR")
            }

            @Test("falls back to person property when override blank")
            func fallsBackToPersonProperty() {
                let result = detectSurveyLanguage(
                    overrideLanguage: " ",
                    personProperties: ["language": "de"],
                    deviceLocale: "en-US"
                )
                #expect(result == "de")
            }

            @Test("falls back to device locale when override and person property absent")
            func fallsBackToDeviceLocale() {
                let result = detectSurveyLanguage(
                    overrideLanguage: nil,
                    personProperties: ["other": "value"],
                    deviceLocale: "en-US"
                )
                #expect(result == "en-US")
            }

            @Test("returns nil when nothing is set")
            func returnsNilWhenNothingSet() {
                let result = detectSurveyLanguage(
                    overrideLanguage: nil,
                    personProperties: nil,
                    deviceLocale: nil
                )
                #expect(result == nil)
            }

            @Test("ignores non-string person language")
            func ignoresNonStringPersonLanguage() {
                let result = detectSurveyLanguage(
                    overrideLanguage: nil,
                    personProperties: ["language": 42],
                    deviceLocale: "en-US"
                )
                #expect(result == "en-US")
            }
        }

        @Suite("Test translation matching")
        struct TestTranslationMatching {
            @Test("returns exact match")
            func exactMatch() {
                let translations = ["fr": "x", "pt-BR": "y"]
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "fr") == "fr")
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "pt-BR") == "pt-BR")
            }

            @Test("is case insensitive and preserves original key casing")
            func caseInsensitiveOriginalCasing() {
                let translations = ["Fr": "x", "PT-br": "y"]
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "fr") == "Fr")
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "PT-BR") == "PT-br")
            }

            @Test("falls back to base language when target has hyphen")
            func baseLanguageFallback() {
                let translations = ["pt": "x"]
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "pt-BR") == "pt")
            }

            @Test("prefers exact match over base language")
            func prefersExactMatch() {
                let translations = ["pt": "base", "pt-BR": "exact"]
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "pt-BR") == "pt-BR")
            }

            @Test("does not fall back when target has no hyphen")
            func noBaseFallbackWithoutHyphen() {
                let translations = ["pt-BR": "x"]
                #expect(findBestTranslationMatch(translations: translations, targetLanguage: "pt") == nil)
            }

            @Test("returns nil for empty inputs")
            func emptyInputs() {
                #expect(findBestTranslationMatch(translations: [String: String](), targetLanguage: "fr") == nil)
                #expect(findBestTranslationMatch(translations: nil as [String: String]?, targetLanguage: "fr") == nil)
                #expect(findBestTranslationMatch(translations: ["fr": "x"], targetLanguage: nil) == nil)
                #expect(findBestTranslationMatch(translations: ["fr": "x"], targetLanguage: "") == nil)
                #expect(findBestTranslationMatch(translations: ["fr": "x"], targetLanguage: "  ") == nil)
            }
        }

        @Suite("Test translation resolution")
        struct TestTranslationResolution {
            @Test("survey decodes translations field")
            func surveyDecodesTranslations() throws {
                let data = try loadFixture("fixture_survey_translations")
                let survey = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)
                #expect(survey.translations?["fr"]?.name == "Bonjour")
                #expect(survey.translations?["fr"]?.thankYouMessageHeader == "Merci!")
                #expect(survey.translations?["pt"]?.thankYouMessageHeader == "Obrigado")
            }

            @Test("question decodes translations field")
            func questionDecodesTranslations() throws {
                let data = try loadFixture("fixture_survey_translations")
                let survey = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)
                if case let .rating(rating) = survey.questions[0] {
                    #expect(rating.translations?["fr"]?.question == "Comment etait-ce?")
                    #expect(rating.translations?["fr"]?.lowerBoundLabel == "Mauvais")
                } else {
                    throw TestError("Expected rating question")
                }
                if case let .singleChoice(choice) = survey.questions[1] {
                    #expect(choice.translations?["fr"]?.choices == ["Un", "Deux"])
                } else {
                    throw TestError("Expected single choice question")
                }
            }

            @Test("returns empty resolution when target language is nil")
            func emptyResolutionWhenTargetNil() throws {
                let survey = try decodeTranslationsFixture()
                let resolved = resolveSurveyTranslations(survey: survey, targetLanguage: nil)
                #expect(resolved.matchedKey == nil)
                #expect(resolved.survey == nil)
                #expect(resolved.questions.allSatisfy { $0 == nil })
            }

            @Test("matches exact language")
            func matchesExactLanguage() throws {
                let survey = try decodeTranslationsFixture()
                let resolved = resolveSurveyTranslations(survey: survey, targetLanguage: "fr")
                #expect(resolved.matchedKey == "fr")
                #expect(resolved.survey?.name == "Bonjour")
                #expect(resolved.questions[0]?.question == "Comment etait-ce?")
                #expect(resolved.questions[1]?.choices == ["Un", "Deux"])
            }

            @Test("falls back to base language")
            func baseLanguageFallback() throws {
                let survey = try decodeTranslationsFixture()
                let resolved = resolveSurveyTranslations(survey: survey, targetLanguage: "pt-BR")
                #expect(resolved.matchedKey == "pt")
                #expect(resolved.survey?.thankYouMessageHeader == "Obrigado")
            }

            @Test("returns nil matchedKey when translations exist but none match")
            func nilWhenNoMatch() throws {
                let survey = try decodeTranslationsFixture()
                let resolved = resolveSurveyTranslations(survey: survey, targetLanguage: "ja")
                #expect(resolved.matchedKey == nil)
                #expect(resolved.survey == nil)
                #expect(resolved.questions.allSatisfy { $0 == nil })
            }

            @Test("returns nil matchedKey when translation matches but values are identical")
            func nilWhenTranslationIsNoop() throws {
                let data = try loadFixture("fixture_survey_translation_noop")
                let survey = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)
                let resolved = resolveSurveyTranslations(survey: survey, targetLanguage: "fr")
                #expect(resolved.matchedKey == nil)
                #expect(resolved.survey == nil)
                #expect(resolved.questions.allSatisfy { $0 == nil })
            }

            private func decodeTranslationsFixture() throws -> PostHogSurvey {
                let data = try loadFixture("fixture_survey_translations")
                return try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)
            }
        }

        @Suite("Test survey_language event property", .serialized)
        class TestSurveyLanguageEventProperty {
            let server: MockPostHogServer
            let postHog: PostHogSDK

            init() {
                server = MockPostHogServer()
                server.start()
                postHog = Self.getSut()
            }

            deinit {
                // Tear down in deinit so a `#require` throwing in a test body can't leak the SDK
                // (and its person-property subscription) into the next serialized test.
                postHog.close()
                postHog.reset()
                server.stop()
            }

            private static func getSut() -> PostHogSDK {
                let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
                config._surveys = true
                config.flushAt = 1
                config.disableReachabilityForTesting = true
                config.disableQueueTimerForTesting = true
                config.disableFlushOnBackgroundForTesting = true
                config.captureApplicationLifecycleEvents = false
                let storage = PostHogStorage(config)
                storage.reset()
                return PostHogSDK.with(config)
            }

            private func getSurveyIntegration(_ postHog: PostHogSDK) throws -> PostHogSurveyIntegration {
                PostHogSurveyIntegration.clearInstalls()
                let integration = PostHogSurveyIntegration()
                let installResult = integration.install(postHog)
                try #require(installResult == .installed)
                return integration
            }

            private func minimalSurvey() -> PostHogSurvey {
                PostHogSurvey(
                    id: "translated-survey",
                    name: "Original",
                    type: .popover,
                    questions: [.open(PostHogOpenSurveyQuestion(
                        id: "q1",
                        question: "Question?",
                        description: nil,
                        descriptionContentType: .text,
                        optional: false,
                        buttonText: nil,
                        originalQuestionIndex: 0,
                        branching: nil,
                        translations: nil
                    ))],
                    featureFlagKeys: nil,
                    linkedFlagKey: nil,
                    targetingFlagKey: nil,
                    internalTargetingFlagKey: nil,
                    conditions: nil,
                    appearance: nil,
                    currentIteration: nil,
                    currentIterationStartDate: nil,
                    startDate: Date(),
                    endDate: nil,
                    schedule: nil,
                    translations: nil
                )
            }

            @Test("survey shown stamps $survey_language when language is set")
            func surveyShownStampsLanguage() async throws {
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyShownEvent(survey: minimalSurvey(), language: "fr")
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].event == "survey shown")
                #expect(events[0].properties["$survey_language"] as? String == "fr")
            }

            @Test("survey shown omits $survey_language when no language matched")
            func surveyShownOmitsLanguageWhenNil() async throws {
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyShownEvent(survey: minimalSurvey(), language: nil)
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].properties["$survey_language"] == nil)
            }

            @Test("survey sent stamps $survey_language when set")
            func surveySentStampsLanguage() async throws {
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveySentEvent(
                    survey: minimalSurvey(),
                    responses: ["$survey_response": .openEnded("ok")],
                    language: "pt"
                )
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].event == "survey sent")
                #expect(events[0].properties["$survey_language"] as? String == "pt")
            }

            @Test("survey sent carries translated question text in $survey_questions")
            func surveySentCarriesTranslatedQuestionText() async throws {
                let integration = try getSurveyIntegration(postHog)
                let translation = PostHogSurveyQuestionTranslation(
                    question: "Question traduite?",
                    description: nil,
                    buttonText: nil,
                    link: nil,
                    lowerBoundLabel: nil,
                    upperBoundLabel: nil,
                    choices: nil
                )
                integration.testSendSurveySentEvent(
                    survey: minimalSurvey(),
                    responses: ["$survey_response": .openEnded("ok")],
                    language: "fr",
                    questionTranslations: [translation]
                )
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                let questions = events[0].properties["$survey_questions"] as? [[String: Any]]
                #expect(questions?.first?["question"] as? String == "Question traduite?")
            }

            @Test("survey dismissed stamps $survey_language when set")
            func surveyDismissedStampsLanguage() async throws {
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyDismissedEvent(survey: minimalSurvey(), language: "fr")
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].event == "survey dismissed")
                #expect(events[0].properties["$survey_language"] as? String == "fr")
            }

            @Test("survey dismissed omits $survey_language when nil")
            func surveyDismissedOmitsLanguageWhenNil() async throws {
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyDismissedEvent(survey: minimalSurvey(), language: nil)
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].properties["$survey_language"] == nil)
            }
        }

        #if os(iOS)
            final class SpySurveysDelegate: NSObject, PostHogSurveysDelegate {
                var updatedSurveys: [PostHogDisplaySurvey] = []

                func renderSurvey(
                    _: PostHogDisplaySurvey,
                    onSurveyShown _: @escaping OnPostHogSurveyShown,
                    onSurveyResponse _: @escaping OnPostHogSurveyResponse,
                    onSurveyClosed _: @escaping OnPostHogSurveyClosed
                ) {}

                func updateSurvey(_ survey: PostHogDisplaySurvey) {
                    updatedSurveys.append(survey)
                }

                func cleanupSurveys() {}
            }

            /// A delegate that does not implement the optional `updateSurvey`.
            final class NoLiveUpdateSurveysDelegate: NSObject, PostHogSurveysDelegate {
                func renderSurvey(
                    _: PostHogDisplaySurvey,
                    onSurveyShown _: @escaping OnPostHogSurveyShown,
                    onSurveyResponse _: @escaping OnPostHogSurveyResponse,
                    onSurveyClosed _: @escaping OnPostHogSurveyClosed
                ) {}

                func cleanupSurveys() {}
            }

            @Suite("Test live translation updates", .serialized)
            class TestLiveTranslationUpdate {
                let server: MockPostHogServer
                let postHog: PostHogSDK

                init() {
                    server = MockPostHogServer()
                    server.start()
                    postHog = Self.getSut()
                }

                deinit {
                    // Tear down in deinit so a `#require` throwing in a test body can't leak the SDK
                    // (and its person-property subscription) into the next serialized test.
                    postHog.close()
                    postHog.reset()
                    server.stop()
                }

                private static func getSut() -> PostHogSDK {
                    let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
                    config._surveys = true
                    config.flushAt = 1
                    config.disableReachabilityForTesting = true
                    config.disableQueueTimerForTesting = true
                    config.disableFlushOnBackgroundForTesting = true
                    config.captureApplicationLifecycleEvents = false
                    let storage = PostHogStorage(config)
                    storage.reset()
                    return PostHogSDK.with(config)
                }

                private func getSurveyIntegration(_ postHog: PostHogSDK) throws -> PostHogSurveyIntegration {
                    PostHogSurveyIntegration.clearInstalls()
                    let integration = PostHogSurveyIntegration()
                    let installResult = integration.install(postHog)
                    try #require(installResult == .installed)
                    return integration
                }

                private func translatedSurvey() -> PostHogSurvey {
                    PostHogSurvey(
                        id: "translated-survey",
                        name: "Original",
                        type: .popover,
                        questions: [.open(PostHogOpenSurveyQuestion(
                            id: "q1",
                            question: "Question?",
                            description: nil,
                            descriptionContentType: .text,
                            optional: false,
                            buttonText: nil,
                            originalQuestionIndex: 0,
                            branching: nil,
                            translations: ["fr": PostHogSurveyQuestionTranslation(
                                question: "Question FR?",
                                description: nil,
                                buttonText: nil,
                                link: nil,
                                lowerBoundLabel: nil,
                                upperBoundLabel: nil,
                                choices: nil
                            )]
                        ))],
                        featureFlagKeys: nil,
                        linkedFlagKey: nil,
                        targetingFlagKey: nil,
                        internalTargetingFlagKey: nil,
                        conditions: nil,
                        appearance: nil,
                        currentIteration: nil,
                        currentIterationStartDate: nil,
                        startDate: Date(),
                        endDate: nil,
                        schedule: nil,
                        translations: ["fr": PostHogSurveyTranslation(
                            name: "Bonjour",
                            thankYouMessageHeader: nil,
                            thankYouMessageDescription: nil,
                            thankYouMessageCloseButtonText: nil
                        )]
                    )
                }

                /// Lets the main-queue work scheduled by the refresh run before asserting.
                private func drainMainQueue() async {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.main.async { continuation.resume() }
                    }
                }

                @Test("changing the language person property re-translates the active survey")
                func languageChangeRetranslatesActiveSurvey() async throws {
                    let spy = SpySurveysDelegate()
                    // Use the backing property directly: the public `surveysConfig` accessor is
                    // gated to iOS 15+, but the delegate it exposes is not version-specific.
                    postHog.config._surveysConfig.surveysDelegate = spy
                    let integration = try getSurveyIntegration(postHog)

                    integration.setShownSurvey(translatedSurvey(), language: nil)
                    postHog.setPersonPropertiesForFlags(["language": "fr"], reloadFeatureFlags: false)
                    await drainMainQueue()

                    #expect(integration.testActiveSurveyLanguage == "fr")
                    #expect(spy.updatedSurveys.count == 1)
                    #expect(spy.updatedSurveys.first?.name == "Bonjour")
                    #expect(spy.updatedSurveys.first?.questions.first?.question == "Question FR?")
                }

                @Test("re-resolving the same language does not push an update")
                func sameLanguageIsNoop() async throws {
                    let spy = SpySurveysDelegate()
                    // Use the backing property directly: the public `surveysConfig` accessor is
                    // gated to iOS 15+, but the delegate it exposes is not version-specific.
                    postHog.config._surveysConfig.surveysDelegate = spy
                    let integration = try getSurveyIntegration(postHog)

                    // Already showing the French translation
                    integration.setShownSurvey(
                        translatedSurvey(),
                        language: "fr",
                        questionTranslations: [PostHogSurveyQuestionTranslation(
                            question: "Question FR?",
                            description: nil,
                            buttonText: nil,
                            link: nil,
                            lowerBoundLabel: nil,
                            upperBoundLabel: nil,
                            choices: nil
                        )]
                    )

                    postHog.setPersonPropertiesForFlags(["language": "fr"], reloadFeatureFlags: false)
                    await drainMainQueue()

                    #expect(integration.testActiveSurveyLanguage == "fr")
                    #expect(spy.updatedSurveys.isEmpty)
                }

                @Test("delegate without updateSurvey keeps the rendered language")
                func delegateWithoutUpdateSurveyKeepsState() async throws {
                    // Use the backing property directly: the public `surveysConfig` accessor is
                    // gated to iOS 15+, but the delegate it exposes is not version-specific.
                    postHog.config._surveysConfig.surveysDelegate = NoLiveUpdateSurveysDelegate()
                    let integration = try getSurveyIntegration(postHog)

                    integration.setShownSurvey(translatedSurvey(), language: nil)
                    postHog.setPersonPropertiesForFlags(["language": "fr"], reloadFeatureFlags: false)
                    await drainMainQueue()

                    // Internal state must not advance past what was actually rendered.
                    #expect(integration.testActiveSurveyLanguage == nil)
                }

                @Test("resetting person properties reverts the active survey language")
                func resetRevertsActiveSurveyLanguage() async throws {
                    let spy = SpySurveysDelegate()
                    // Use the backing property directly: the public `surveysConfig` accessor is
                    // gated to iOS 15+, but the delegate it exposes is not version-specific.
                    postHog.config._surveysConfig.surveysDelegate = spy
                    let integration = try getSurveyIntegration(postHog)

                    integration.setShownSurvey(translatedSurvey(), language: nil)
                    postHog.setPersonPropertiesForFlags(["language": "fr"], reloadFeatureFlags: false)
                    await drainMainQueue()
                    try #require(integration.testActiveSurveyLanguage == "fr")

                    postHog.resetPersonPropertiesForFlags(reloadFeatureFlags: false)
                    await drainMainQueue()

                    #expect(integration.testActiveSurveyLanguage == nil)
                    #expect(spy.updatedSurveys.count == 2)
                    #expect(spy.updatedSurveys.last?.name == "Original")
                }

                @Test("no active survey means no update is pushed")
                func noActiveSurveyIsNoop() async throws {
                    let spy = SpySurveysDelegate()
                    // Use the backing property directly: the public `surveysConfig` accessor is
                    // gated to iOS 15+, but the delegate it exposes is not version-specific.
                    postHog.config._surveysConfig.surveysDelegate = spy
                    _ = try getSurveyIntegration(postHog)

                    postHog.setPersonPropertiesForFlags(["language": "fr"], reloadFeatureFlags: false)
                    await drainMainQueue()

                    #expect(spy.updatedSurveys.isEmpty)
                }

                @Test("survey shown reconciles a language change that landed before display")
                func showReconcilesPreDisplayLanguageChange() async throws {
                    let spy = SpySurveysDelegate()
                    postHog.config._surveysConfig.surveysDelegate = spy
                    let integration = try getSurveyIntegration(postHog)

                    // Survey is set up (rendered) in the base language but not yet shown.
                    integration.setShownSurvey(translatedSurvey(), language: nil)

                    // A language change commits before the survey reaches the screen. On a real
                    // controller this update is dropped (nothing displayed yet); the tracked language
                    // still advances to `fr`.
                    postHog.setPersonPropertiesForFlags(["language": "fr"], reloadFeatureFlags: false)
                    await drainMainQueue()
                    try #require(integration.testActiveSurveyLanguage == "fr")
                    let updatesBeforeShow = spy.updatedSurveys.count

                    // When the survey is finally shown, the missed translation is reconciled.
                    integration.testHandleSurveyShown(survey: translatedSurvey().toDisplaySurvey())
                    await drainMainQueue()

                    #expect(spy.updatedSurveys.count == updatesBeforeShow + 1)
                    #expect(spy.updatedSurveys.last?.name == "Bonjour")
                    #expect(spy.updatedSurveys.last?.questions.first?.question == "Question FR?")
                }

                @Test("survey shown does not reconcile when the rendered language is current")
                func showDoesNotReconcileWhenLanguageUnchanged() async throws {
                    let spy = SpySurveysDelegate()
                    postHog.config._surveysConfig.surveysDelegate = spy
                    let integration = try getSurveyIntegration(postHog)

                    integration.setShownSurvey(translatedSurvey(), language: nil)
                    integration.testHandleSurveyShown(survey: translatedSurvey().toDisplaySurvey())
                    await drainMainQueue()

                    #expect(spy.updatedSurveys.isEmpty)
                }
            }

            @Suite("Test display controller in-place update")
            struct TestDisplayControllerUpdate {
                private func displaySurvey(name: String) -> PostHogDisplaySurvey {
                    PostHogDisplaySurvey(
                        id: "survey-1",
                        name: name,
                        questions: [],
                        appearance: nil,
                        startDate: nil,
                        endDate: nil
                    )
                }

                @MainActor
                @Test("update preserves question index and completion state")
                func updatePreservesProgress() {
                    let controller = SurveyDisplayController()
                    controller.showSurvey(displaySurvey(name: "Original"))
                    controller.currentQuestionIndex = 2
                    controller.isSurveyCompleted = true

                    controller.updateSurvey(displaySurvey(name: "Bonjour"))

                    #expect(controller.displayedSurvey?.name == "Bonjour")
                    #expect(controller.currentQuestionIndex == 2)
                    #expect(controller.isSurveyCompleted == true)
                }

                @MainActor
                @Test("update for a different survey id is ignored")
                func updateDifferentSurveyIgnored() {
                    let controller = SurveyDisplayController()
                    controller.showSurvey(displaySurvey(name: "Original"))

                    let other = PostHogDisplaySurvey(
                        id: "survey-2",
                        name: "Other",
                        questions: [],
                        appearance: nil,
                        startDate: nil,
                        endDate: nil
                    )
                    controller.updateSurvey(other)

                    #expect(controller.displayedSurvey?.name == "Original")
                }

                @MainActor
                @Test("update with no displayed survey is ignored")
                func updateWithNoSurveyIgnored() {
                    let controller = SurveyDisplayController()
                    controller.updateSurvey(displaySurvey(name: "Bonjour"))
                    #expect(controller.displayedSurvey == nil)
                }
            }

            @Suite("Test default delegate delayed display update", .serialized)
            struct TestDefaultDelegateDelayedDisplay {
                private func displaySurvey(name: String, delaySeconds: TimeInterval) -> PostHogDisplaySurvey {
                    PostHogDisplaySurvey(
                        id: "survey-1",
                        name: name,
                        questions: [],
                        appearance: PostHogDisplaySurveyAppearance(
                            fontFamily: nil,
                            backgroundColor: nil,
                            borderColor: nil,
                            submitButtonColor: nil,
                            submitButtonText: nil,
                            submitButtonTextColor: nil,
                            textColor: nil,
                            descriptionTextColor: nil,
                            ratingButtonColor: nil,
                            ratingButtonActiveColor: nil,
                            inputBackground: nil,
                            inputTextColor: nil,
                            placeholder: nil,
                            surveyPopupDelaySeconds: delaySeconds,
                            displayThankYouMessage: false,
                            thankYouMessageHeader: nil,
                            thankYouMessageDescription: nil,
                            thankYouMessageDescriptionContentType: nil,
                            thankYouMessageCloseButtonText: nil
                        ),
                        startDate: nil,
                        endDate: nil
                    )
                }

                @MainActor
                @Test("survey updated during its display delay shows the updated copy")
                func delayedDisplayShowsUpdatedCopy() async throws {
                    let delegate = PostHogSurveysDefaultDelegate()
                    let controller = SurveyDisplayController()
                    delegate.setDisplayControllerForTesting(controller)

                    delegate.renderSurvey(
                        displaySurvey(name: "Original", delaySeconds: 0.1),
                        onSurveyShown: { _ in },
                        onSurveyResponse: { _, _, _ in nil },
                        onSurveyClosed: { _ in }
                    )
                    #expect(controller.displayedSurvey == nil)

                    delegate.updateSurvey(displaySurvey(name: "Updated", delaySeconds: 0.1))

                    for _ in 0 ..< 100 where controller.displayedSurvey == nil {
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                    #expect(controller.displayedSurvey?.name == "Updated")
                }
            }
        #endif

        @Suite("Test display survey with translations")
        struct TestDisplayTranslation {
            @Test("display survey applies translation fields with fallback")
            func displaySurveyApplies() throws {
                let data = try loadFixture("fixture_survey_translations")
                let survey = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)
                let resolved = resolveSurveyTranslations(survey: survey, targetLanguage: "fr")
                let display = survey.toDisplaySurvey(
                    surveyTranslation: resolved.survey,
                    questionTranslations: resolved.questions
                )
                #expect(display.name == "Bonjour")
                if let rating = display.questions[0] as? PostHogDisplayRatingQuestion {
                    #expect(rating.question == "Comment etait-ce?")
                    #expect(rating.lowerBoundLabel == "Mauvais")
                    // upperBoundLabel was not translated — falls back
                    #expect(rating.upperBoundLabel == "Great")
                } else {
                    throw TestError("Expected rating display question")
                }
                if let choice = display.questions[1] as? PostHogDisplayChoiceQuestion {
                    #expect(choice.choices == ["Un", "Deux"])
                } else {
                    throw TestError("Expected choice display question")
                }
                #expect(display.appearance?.thankYouMessageHeader == "Merci!")
            }

            @Test("display survey without translations renders original")
            func displaySurveyWithoutTranslations() throws {
                let data = try loadFixture("fixture_survey_translations")
                let survey = try PostHogApi.jsonDecoder.decode(PostHogSurvey.self, from: data)
                let display = survey.toDisplaySurvey()
                #expect(display.name == "Hello")
                if let rating = display.questions[0] as? PostHogDisplayRatingQuestion {
                    #expect(rating.question == "How was it?")
                    #expect(rating.lowerBoundLabel == "Bad")
                }
                if let choice = display.questions[1] as? PostHogDisplayChoiceQuestion {
                    #expect(choice.choices == ["One", "Two"])
                }
                #expect(display.appearance?.thankYouMessageHeader == "Thanks!")
            }
        }
    }

#endif
