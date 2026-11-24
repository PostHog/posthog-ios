#if !SWIFT_PACKAGE || Surveys
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Survey font family parsing")
    struct SurveyFontFamilyNameTests {
        @Test("Keeps the system font when unset, empty, inherit or system-ui", arguments: [
            nil, "", "  ", "\"\"", "''", ", serif", "inherit", "INHERIT", "system-ui", " 'system-ui', sans-serif",
        ])
        func systemFont(css: String?) {
            #expect(surveyFontFamilyName(css) == nil)
        }

        @Test("Uses the first family of a CSS list, unquoted and trimmed", arguments: [
            ("Georgia", "Georgia"),
            ("Times New Roman", "Times New Roman"),
            ("\"Times New Roman\", serif", "Times New Roman"),
            (" 'Courier New' , monospace", "Courier New"),
            ("Arial,Helvetica,sans-serif", "Arial"),
            ("  \" Trebuchet MS \"  ", "Trebuchet MS"),
        ])
        func firstFamily(css: String, expected: String) {
            #expect(surveyFontFamilyName(css) == expected)
        }
    }

    #if os(iOS)
        import UIKit

        @Suite("Survey font family resolution")
        struct SurveyFontResolutionTests {
            @Test("Picker fonts installed on iOS resolve by family name", arguments: [
                "Arial", "Verdana", "Trebuchet MS", "Helvetica", "Times New Roman", "Georgia", "Courier New",
                "\"Times New Roman\", serif", "arial",
            ])
            func installedFont(css: String) throws {
                let name = try #require(resolveSurveyFontName(css))
                let font = try #require(UIFont(name: name, size: 17))
                #expect(font.familyName.caseInsensitiveCompare(surveyFontFamilyName(css) ?? "") == .orderedSame)
            }

            @Test("System keywords and unavailable fonts fall back to the system font", arguments: [
                nil, "", "inherit", "system-ui", "Tahoma", "Not A Real Font",
            ])
            func systemFallback(css: String?) {
                #expect(resolveSurveyFontName(css) == nil)
            }

            @Test("System font rendering is unchanged without a custom font")
            func systemRendering() {
                let appearance = SwiftUISurveyAppearance.getAppearanceWithDefaults()
                #expect(appearance.font(.body) == .body)
                #expect(appearance.font(.body, bold: true) == .body.bold())
                #expect(appearance.font(.callout) == .callout)
            }

            @Test("Custom fonts keep the text style's size and Dynamic Type scaling")
            func customFontScales() throws {
                let appearance = SwiftUISurveyAppearance.getAppearanceWithDefaults(
                    PostHogDisplaySurveyAppearance(
                        fontFamily: "Georgia", backgroundColor: nil, borderColor: nil, submitButtonColor: nil,
                        submitButtonText: nil, submitButtonTextColor: nil, textColor: nil, descriptionTextColor: nil,
                        ratingButtonColor: nil, ratingButtonActiveColor: nil, inputBackground: nil, inputTextColor: nil,
                        placeholder: nil, surveyPopupDelaySeconds: nil, displayThankYouMessage: true, thankYouMessageHeader: nil,
                        thankYouMessageDescription: nil, thankYouMessageDescriptionContentType: nil,
                        thankYouMessageCloseButtonText: nil
                    )
                )
                let name = try #require(appearance.fontName)
                #expect(appearance.font(.body) == .custom(name, size: 17, relativeTo: .body))
                #expect(appearance.font(.callout) == .custom(name, size: 16, relativeTo: .callout))
                #expect(appearance.font(.body, bold: true) == .custom(name, size: 17, relativeTo: .body).bold())
            }
        }
    #endif
#endif
