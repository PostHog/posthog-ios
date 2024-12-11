// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "PostHog",
    platforms: [
        // TODO: add  .visionOS(.v1), when SPM is >= 5.9
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "PostHog",
            targets: ["PostHog"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/Quick/Quick.git", from: "6.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "12.0.0"),
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs.git", from: "9.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "PostHog",
            dependencies: ["libwebp"],
            path: "PostHog",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),
        .target(
            name: "libwebp",
            path: "vendor",
            sources: ["libwebp/src", "libwebp/sharpyuv", "include"],
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .testTarget(
            name: "PostHogTests",
            dependencies: [
                "PostHog",
                "Quick",
                "Nimble",
                "OHHTTPStubs",
                .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs"),
            ],
            path: "PostHogTests",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
