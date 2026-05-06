import Foundation

/// Parses a `CFBundleVersion` string as an `Int` when possible, falling back to the
/// raw `String`. Apple allows both numeric (`"42"`) and dotted (`"1.2.3"`) build
/// numbers, so a parse failure is expected and not an error.
func parseBundleVersion(_ value: String) -> Any {
    Int(value) ?? value
}

/// Reads `CFBundleShortVersionString` from the main bundle. Nil for command-line
/// tools / XCTest hosts that lack an Info.plist short version string.
func appVersionString() -> String? {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
}

/// Current OS version as `"<major>.<minor>.<patch>"`. Caller decides on units
/// (PostHog uses this for both the `$os_version` event property and the
/// `os.version` OTLP resource attribute).
func osVersionString() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

/// `Bundle.main.bundleIdentifier` with a caller-supplied fallback. Apps almost
/// always have a bundle id; fallbacks cover command-line tools / test hosts /
/// Swift Playgrounds that don't.
func bundleIdentifier(fallback: String) -> String {
    Bundle.main.bundleIdentifier ?? fallback
}
