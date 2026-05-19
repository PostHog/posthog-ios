//
//  SurveyTranslationResolver.swift
//  PostHog
//
//  Created by PostHog Code on 2026-05-13.
//

#if os(iOS) || TESTING

    import Foundation

    /// `matchedKey` is the original-cased key from a `translations` dictionary that drove
    /// the change (preferring the survey-level key when both survey and question matched),
    /// or `nil` when no user-visible field actually changed. `questions` is indexed
    /// positionally against `survey.questions`.
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
        let findKey: (String) -> String? = { target in
            translations.keys.first(where: { $0.lowercased() == target })
        }

        if let exact = findKey(normalizedTarget) { return exact }

        if let hyphen = normalizedTarget.firstIndex(of: "-") {
            let base = String(normalizedTarget[..<hyphen])
            if let baseMatch = findKey(base) { return baseMatch }
        }

        return nil
    }

    /// Returns a non-nil `matchedKey` only when applying the matched translation would
    /// actually change a user-visible field — so callers don't stamp `$survey_language`
    /// onto events when nothing on screen changed.
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

        var firstQuestionKey: String?
        var questionTranslations: [PostHogSurveyQuestionTranslation?] = []
        for question in survey.questions {
            let key = findBestTranslationMatch(
                translations: question.translations,
                targetLanguage: targetLanguage
            )
            let translation = key.flatMap { question.translations?[$0] }
            let changes = translation.map { questionTranslationChangesAnything(question: question, translation: $0) } ?? false
            questionTranslations.append(changes ? translation : nil)
            if changes, firstQuestionKey == nil { firstQuestionKey = key }
        }

        if !surveyChanged, firstQuestionKey == nil { return empty }

        // Prefer the survey-level key if it actually drove a change; otherwise fall back
        // to whichever question's translation key did. In the common case both refer to
        // the same target language and the choice is purely cosmetic.
        let matchedKey = surveyChanged ? surveyKey : firstQuestionKey

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
