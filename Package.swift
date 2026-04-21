// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "PostHog",
    platforms: [
        // visionOS is supported via Package@swift-5.9.swift for Swift 5.9+ users
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
            dependencies: [
                "phlibwebp",
                "PHPLCrashReporter",
            ],
            path: "PostHog",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),
        .target(
            name: "phlibwebp",
            path: "vendor/libwebp",
            publicHeadersPath: ".",
            cSettings: [
                .define("PLCR_PRIVATE"),
                .headerSearchPath("."),
            ]
        ),
        .target(
            name: "PHPLCrashReporter",
            path: "vendor/PHPLCrashReporter",
            exclude: [
                "Source/dwarf_opstream.hpp",
                "Source/dwarf_stack.hpp",
                "Source/PLCrashAsyncDwarfCFAState.hpp",
                "Source/PLCrashAsyncDwarfCIE.hpp",
                "Source/PLCrashAsyncDwarfEncoding.hpp",
                "Source/PLCrashAsyncDwarfExpression.hpp",
                "Source/PLCrashAsyncDwarfFDE.hpp",
                "Source/PLCrashAsyncDwarfPrimitives.hpp",
                "Source/PLCrashAsyncLinkedList.hpp",
                "Source/PLCrashReport.proto",
                "Dependencies/protobuf-c/generate-pb-c.sh",
                "LICENSE",
            ],
            sources: [
                "Source",
                "Dependencies/protobuf-c",
            ],
            resources: [.process("Resources/PrivacyInfo.xcprivacy")],
            publicHeadersPath: "include",
            cSettings: [
                .define("PLCR_PRIVATE"),
                .define("PLCF_RELEASE_BUILD"),
                .define("SWIFT_PACKAGE"),
                .headerSearchPath("Dependencies/protobuf-c"),
                .headerSearchPath("Source"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
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
