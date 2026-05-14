//
//  SurveyTranslationResolver.swift
//  PostHog
//
//  Created by PostHog Code on 2026-05-13.
//

#if os(iOS) || TESTING

    import Foundation

    /// Outcome of resolving translations for one survey at display time.
    ///
    /// - `matchedKey`: the original-cased key from a `translations` dictionary that drove
    ///   the change (preferring the survey-level key when both survey and question matched).
    ///   `nil` when no translation was applied at all.
    /// - `survey`: the resolved survey-level translation, or `nil` if none matched.
    /// - `questions`: per-question translation, indexed positionally against
    ///   `survey.questions`. `nil` entries leave the question untranslated.
    struct ResolvedSurveyTranslations {
        let matchedKey: String?
        let survey: PostHogSurveyTranslation?
        let questions: [PostHogSurveyQuestionTranslation?]
    }

    /// Resolves the language code to use for survey translation, in priority order:
    ///
    /// 1. Explicit SDK override (`PostHogSurveysConfig.overrideDisplayLanguage`).
    /// 2. The `"language"` key of the persisted person properties (set via
    ///    `identify(..., userProperties: ["language": "fr"])`).
    /// 3. The device locale (BCP-47 form — underscores converted to hyphens).
    func detectSurveyLanguage(
        overrideLanguage: String?,
        personProperties: [String: Any]?,
        deviceLocale: String?
    ) -> String? {
        if let override = overrideLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return override
        }

        if let personLanguage = personProperties?[personPropertyLanguageKey] as? String {
            let trimmed = personLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let locale = deviceLocale?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locale.isEmpty
        {
            return locale
        }

        return nil
    }

    /// Finds the best matching translation key in `translations` for `targetLanguage`.
    ///
    /// Matching is case-insensitive. If no exact match is found and the target contains a
    /// region suffix (e.g. `"pt-BR"`), the base language (e.g. `"pt"`) is tried as a
    /// fallback.
    ///
    /// Returns the original-cased key from `translations` (so it can be reported verbatim
    /// as `$survey_language`), or `nil` if no match.
    func findBestTranslationMatch<T>(
        translations: [String: T]?,
        targetLanguage: String?
    ) -> String? {
        guard let translations, !translations.isEmpty,
              let target = targetLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty
        else {
            return nil
        }

        let normalizedTarget = target.lowercased()

        if let exact = translations.keys.first(where: { $0.lowercased() == normalizedTarget }) {
            return exact
        }

        if let hyphen = normalizedTarget.firstIndex(of: "-") {
            let base = String(normalizedTarget[..<hyphen])
            if let baseMatch = translations.keys.first(where: { $0.lowercased() == base }) {
                return baseMatch
            }
        }

        return nil
    }

    /// Resolves which translations should be applied to `survey` given the user's
    /// `targetLanguage`. Tracks whether the resolution actually changed any user-visible
    /// field; if not, `matchedKey` is `nil` so callers don't mistakenly stamp
    /// `$survey_language` onto events.
    func resolveSurveyTranslations(
        survey: PostHogSurvey,
        targetLanguage: String?
    ) -> ResolvedSurveyTranslations {
        let empty = ResolvedSurveyTranslations(
            matchedKey: nil,
            survey: nil,
            questions: Array(repeating: nil, count: survey.questions.count)
        )

        guard let targetLanguage,
              !targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return empty
        }

        let surveyKey = findBestTranslationMatch(
            translations: survey.translations,
            targetLanguage: targetLanguage
        )
        let surveyTranslation = surveyKey.flatMap { survey.translations?[$0] }
        let surveyChanged = surveyTranslation.map { surveyTranslationChangesAnything(survey: survey, translation: $0) } ?? false

        var anyQuestionChanged = false
        var questionTranslations: [PostHogSurveyQuestionTranslation?] = []
        var questionKeys: [String?] = []
        for question in survey.questions {
            let key = findBestTranslationMatch(
                translations: question.translations,
                targetLanguage: targetLanguage
            )
            let translation = key.flatMap { question.translations?[$0] }
            let changes = translation.map { questionTranslationChangesAnything(question: question, translation: $0) } ?? false
            if changes {
                anyQuestionChanged = true
                questionTranslations.append(translation)
                questionKeys.append(key)
            } else {
                questionTranslations.append(nil)
                questionKeys.append(nil)
            }
        }

        if !surveyChanged, !anyQuestionChanged { return empty }

        let matchedKey: String?
        if surveyChanged {
            matchedKey = surveyKey
        } else {
            matchedKey = questionKeys.compactMap { $0 }.first
        }

        return ResolvedSurveyTranslations(
            matchedKey: matchedKey,
            survey: surveyChanged ? surveyTranslation : nil,
            questions: questionTranslations
        )
    }

    private func surveyTranslationChangesAnything(
        survey: PostHogSurvey,
        translation: PostHogSurveyTranslation
    ) -> Bool {
        if let name = translation.name, name != survey.name { return true }
        let appearance = survey.appearance
        if let header = translation.thankYouMessageHeader,
           header != appearance?.thankYouMessageHeader { return true }
        if let description = translation.thankYouMessageDescription,
           description != appearance?.thankYouMessageDescription { return true }
        if let closeText = translation.thankYouMessageCloseButtonText,
           closeText != appearance?.thankYouMessageCloseButtonText { return true }
        return false
    }

    private func questionTranslationChangesAnything(
        question: PostHogSurveyQuestion,
        translation: PostHogSurveyQuestionTranslation
    ) -> Bool {
        if let translated = translation.question, translated != question.question { return true }
        if let translated = translation.description, translated != question.description { return true }
        if let translated = translation.buttonText, translated != question.buttonText { return true }

        switch question {
        case let .link(link):
            if let translated = translation.link, translated != link.link { return true }
        case let .rating(rating):
            if let translated = translation.lowerBoundLabel, translated != rating.lowerBoundLabel { return true }
            if let translated = translation.upperBoundLabel, translated != rating.upperBoundLabel { return true }
        case let .singleChoice(choice), let .multipleChoice(choice):
            if let translated = translation.choices, translated != choice.choices { return true }
        case .open, .unknown:
            break
        }

        return false
    }

    private let personPropertyLanguageKey = "language"

#endif
