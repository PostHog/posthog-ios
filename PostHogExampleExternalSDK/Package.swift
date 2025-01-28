// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ExternalSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "ExternalSDK",
            targets: ["ExternalSDK-iOS"]
        ),
    ],
    dependencies: [
        .package(path: "../"),
    ],
    targets: [
        .target(
            name: "ExternalSDK-iOS",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios"),
                .target(name: "ExternalSDK"),
            ]
        ),
        .binaryTarget(name: "ExternalSDK", path: "./build/bin/ExternalSDK.xcframework"),
    ]
)
