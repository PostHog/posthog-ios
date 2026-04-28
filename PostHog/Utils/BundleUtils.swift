import Foundation

/// Parses a `CFBundleVersion` string as an `Int` when possible, falling back to the
/// raw `String`. Apple allows both numeric (`"42"`) and dotted (`"1.2.3"`) build
/// numbers, so a parse failure is expected and not an error.
func parseBundleVersion(_ value: String) -> Any {
    Int(value) ?? value
}
