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

            init() {
                server = MockPostHogServer()
                server.start()
            }

            deinit {
                server.stop()
            }

            private func getSut() -> PostHogSDK {
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
                let postHog = getSut()
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyShownEvent(survey: minimalSurvey(), language: "fr")
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].event == "survey shown")
                #expect(events[0].properties["$survey_language"] as? String == "fr")
                postHog.close()
                postHog.reset()
            }

            @Test("survey shown omits $survey_language when no language matched")
            func surveyShownOmitsLanguageWhenNil() async throws {
                let postHog = getSut()
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyShownEvent(survey: minimalSurvey(), language: nil)
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].properties["$survey_language"] == nil)
                postHog.close()
                postHog.reset()
            }

            @Test("survey sent stamps $survey_language when set")
            func surveySentStampsLanguage() async throws {
                let postHog = getSut()
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
                postHog.close()
                postHog.reset()
            }

            @Test("survey sent carries translated question text in $survey_questions")
            func surveySentCarriesTranslatedQuestionText() async throws {
                let postHog = getSut()
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
                postHog.close()
                postHog.reset()
            }

            @Test("survey dismissed stamps $survey_language when set")
            func surveyDismissedStampsLanguage() async throws {
                let postHog = getSut()
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyDismissedEvent(survey: minimalSurvey(), language: "fr")
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].event == "survey dismissed")
                #expect(events[0].properties["$survey_language"] as? String == "fr")
                postHog.close()
                postHog.reset()
            }

            @Test("survey dismissed omits $survey_language when nil")
            func surveyDismissedOmitsLanguageWhenNil() async throws {
                let postHog = getSut()
                let integration = try getSurveyIntegration(postHog)
                integration.testSendSurveyDismissedEvent(survey: minimalSurvey(), language: nil)
                let events = try await getServerEvents(server)
                #expect(events.count == 1)
                #expect(events[0].properties["$survey_language"] == nil)
                postHog.close()
                postHog.reset()
            }
        }

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
