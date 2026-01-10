// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PostHogIOSComplianceAdapter",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(name: "PostHog", path: ".."), // PostHog iOS SDK
    ],
    targets: [
        .executableTarget(
            name: "PostHogIOSComplianceAdapter",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "PostHog",
            ],
            path: "Sources",
            swiftSettings: [
                // Enable TESTING flag to avoid Bundle.main.bundleIdentifier! crash
                .define("TESTING"),
            ]
        ),
    ]
)
