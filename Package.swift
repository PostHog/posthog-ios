// swift-tools-version:5.2

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
//        .testTarget(
//            name: "PostHogTests",
//            dependencies: ["PostHog"],
//            path: "PostHogTests"
//        ),
    ]
)
