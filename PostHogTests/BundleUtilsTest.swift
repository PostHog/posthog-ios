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
}
