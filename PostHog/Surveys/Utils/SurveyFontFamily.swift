//
//  SurveyFontFamily.swift
//  PostHog
//

#if !SWIFT_PACKAGE || Surveys
    import Foundation

    /// Returns the first family of a CSS `font-family` list, unquoted and trimmed,
    /// or nil when the survey should keep the system font (unset, `inherit` or `system-ui`).
    func surveyFontFamilyName(_ css: String?) -> String? {
        guard let css else { return nil }
        let value = css.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        // A quoted family name may itself contain commas.
        if let quote = value.first, quote == "\"" || quote == "'" {
            name = String(value.dropFirst().prefix { $0 != quote })
        } else {
            name = String(value.prefix { $0 != "," })
        }
        let family = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyword = family.lowercased()
        if family.isEmpty || keyword == "inherit" || keyword == "system-ui" { return nil }
        return family
    }
#endif
