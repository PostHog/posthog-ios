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
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

/// Compile-time platform name as a plain string ("iOS" / "macOS" / "tvOS" /
/// "watchOS" / "visionOS"). Used for the OTLP `os.name` resource attribute.
/// Returns "macOS" for Mac Catalyst apps. Distinct from
/// `UIDevice.current.systemName` (which can return "iPadOS") because OTLP
/// semantic conventions use the higher-level family name.
func osName() -> String {
    #if os(visionOS)
        return "visionOS"
    #elseif os(watchOS)
        return "watchOS"
    #elseif os(tvOS)
        return "tvOS"
    #elseif os(macOS) || targetEnvironment(macCatalyst)
        return "macOS"
    #elseif os(iOS)
        return "iOS"
    #else
        return "unknown"
    #endif
}

/// `Bundle.main.bundleIdentifier` with a caller-supplied fallback. Apps almost
/// always have a bundle id; fallbacks cover command-line tools / test hosts /
/// Swift Playgrounds that don't.
func bundleIdentifier(fallback: String) -> String {
    Bundle.main.bundleIdentifier ?? fallback
}
