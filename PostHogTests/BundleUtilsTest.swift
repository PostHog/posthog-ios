import Foundation
@testable import PostHog
import Testing

@Suite("BundleUtilsTest")
struct BundleUtilsTest {
    @Suite("parseBundleVersion")
    struct ParseBundleVersionTests {
        @Test("returns Int when the value is purely numeric")
        func returnsIntForNumericValue() {
            #expect(parseBundleVersion("42") as? Int == 42)
        }

        @Test("returns String when the value contains dots (e.g. semver-style builds)")
        func returnsStringForDottedValue() {
            #expect(parseBundleVersion("1.2.3") as? String == "1.2.3")
        }

        @Test("returns String when the value contains non-numeric characters")
        func returnsStringForAlphanumericValue() {
            #expect(parseBundleVersion("42-beta") as? String == "42-beta")
        }

        @Test("returns String for an empty value")
        func returnsStringForEmptyValue() {
            #expect(parseBundleVersion("") as? String == "")
        }

        @Test("returns Int for zero")
        func returnsIntForZero() {
            #expect(parseBundleVersion("0") as? Int == 0)
        }
    }

    @Suite("appBuildToolchainProperties")
    struct AppBuildToolchainPropertiesTests {
        @Test("reads DTXcode and DTSDKName as-is")
        func readsXcodeAndSdk() {
            let props = appBuildToolchainProperties([
                "DTXcode": "2640",
                "DTXcodeBuild": "17E202",
                "DTSDKName": "iphoneos26.4",
            ])

            #expect(props.count == 2)
            #expect(props["$app_build_xcode"] as? String == "2640")
            #expect(props["$app_build_sdk"] as? String == "iphoneos26.4")
        }

        @Test("omits keys that are missing, empty or not strings")
        func omitsInvalidValues() {
            #expect(appBuildToolchainProperties(nil).isEmpty)
            #expect(appBuildToolchainProperties([:]).isEmpty)
            #expect(appBuildToolchainProperties(["DTXcode": "", "DTSDKName": ""]).isEmpty)
            #expect(appBuildToolchainProperties(["DTXcode": 2640, "DTSDKName": 26.4]).isEmpty)
        }

        @Test("sets each key independently")
        func setsEachKeyIndependently() {
            let props = appBuildToolchainProperties(["DTSDKName": "macosx26.4"])

            #expect(props["$app_build_xcode"] == nil)
            #expect(props["$app_build_sdk"] as? String == "macosx26.4")
        }
    }
}
