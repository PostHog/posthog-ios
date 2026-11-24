//
//  SurveyFontFamily.swift
//  PostHog
//

#if !SWIFT_PACKAGE || Surveys
    import Foundation

    /// Returns the first family of a CSS `font-family` list, unquoted and trimmed,
    /// or nil when the survey should keep the system font (unset, `inherit` or `system-ui`).
    func surveyFontFamilyName(_ css: String?) -> String? {
        guard let first = css?.split(separator: ",", omittingEmptySubsequences: false).first else { return nil }
        let name = first
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keyword = name.lowercased()
        if name.isEmpty || keyword == "inherit" || keyword == "system-ui" { return nil }
        return name
    }
#endif
