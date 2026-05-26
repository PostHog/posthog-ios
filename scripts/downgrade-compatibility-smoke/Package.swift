// swift-tools-version:5.3
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
let dependencyPath = environment["POSTHOG_DOWNGRADE_SMOKE_DEPENDENCY_PATH"] ?? "../.."
let dependencyURL = URL(fileURLWithPath: dependencyPath)
let packageIdentity = dependencyURL.lastPathComponent
    .replacingOccurrences(of: ".git", with: "")
    .lowercased()
let currentWriterSwiftSettings: [SwiftSetting] = environment["POSTHOG_DOWNGRADE_SMOKE_CURRENT_WRITER"] == "1"
    ? [.define("CURRENT_STORAGE_WRITER")]
    : []

let package = Package(
    name: "DowngradeCompatibilitySmoke",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "DowngradeCompatibilitySmoke", targets: ["DowngradeCompatibilitySmoke"]),
    ],
    dependencies: [
        .package(path: dependencyPath),
    ],
    targets: [
        .target(
            name: "DowngradeCompatibilitySmoke",
            dependencies: [.product(name: "PostHog", package: packageIdentity)],
            swiftSettings: currentWriterSwiftSettings
        ),
    ]
)
