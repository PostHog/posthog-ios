AppCode   
// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PostHog",
    products: [
        .library(name: "PostHog", targets: ["PostHog"]),
    ],
    targets: [
        .target(
            name: "PostHog",
            dependencies: [],
			path: "PostHog"
			),
        .testTarget(
            name: "PostHogTests",
            dependencies: ["PostHog"]),
    ]
)