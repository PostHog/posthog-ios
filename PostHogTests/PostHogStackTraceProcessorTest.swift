//
//  PostHogStackTraceProcessorTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 22/12/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogStackTraceProcessor Tests")
struct PostHogStackTraceProcessorTest {
    // MARK: - In-App Detection Tests

    @Suite("In-App Detection")
    struct InAppDetectionTests {
        @Test("marks module as in-app when in inAppIncludes")
        func marksInAppWhenInIncludes() {
            let config = PostHogErrorTrackingConfig()
            config.inAppIncludes = ["MyApp", "SharedModule"]

            #expect(PostHogStackTraceProcessor.isInApp(module: "MyApp", config: config) == true)
            #expect(PostHogStackTraceProcessor.isInApp(module: "MyAppExtension", config: config) == true)
            #expect(PostHogStackTraceProcessor.isInApp(module: "SharedModule", config: config) == true)
        }

        @Test("marks module as not in-app when in inAppExcludes")
        func marksNotInAppWhenInExcludes() {
            let config = PostHogErrorTrackingConfig()
            config.inAppExcludes = ["Alamofire", "SDWebImage"]

            #expect(PostHogStackTraceProcessor.isInApp(module: "Alamofire", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "SDWebImage", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "SDWebImageSwiftUI", config: config) == false)
        }

        @Test("inAppIncludes takes precedence over inAppExcludes")
        func includesTakesPrecedenceOverExcludes() {
            let config = PostHogErrorTrackingConfig()
            config.inAppIncludes = ["MyModule"]
            config.inAppExcludes = ["MyModule"]

            #expect(PostHogStackTraceProcessor.isInApp(module: "MyModule", config: config) == true)
        }

        @Test("marks system frameworks as not in-app")
        func marksSystemFrameworksAsNotInApp() {
            let config = PostHogErrorTrackingConfig()

            #expect(PostHogStackTraceProcessor.isInApp(module: "Foundation", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "UIKit", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "CoreFoundation", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "SwiftUI", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "libsystem_kernel.dylib", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "libswiftCore.dylib", config: config) == false)
        }

        @Test("uses inAppByDefault for unknown modules")
        func usesInAppByDefault() {
            let config = PostHogErrorTrackingConfig()

            config.inAppByDefault = true
            #expect(PostHogStackTraceProcessor.isInApp(module: "UnknownModule", config: config) == true)

            config.inAppByDefault = false
            #expect(PostHogStackTraceProcessor.isInApp(module: "UnknownModule", config: config) == false)
        }

        @Test("uses prefix matching for includes")
        func usesPrefixMatchingForIncludes() {
            let config = PostHogErrorTrackingConfig()
            config.inAppIncludes = ["com.posthog"]
            config.inAppByDefault = false

            #expect(PostHogStackTraceProcessor.isInApp(module: "com.posthog.sdk", config: config) == true)
            #expect(PostHogStackTraceProcessor.isInApp(module: "com.posthog", config: config) == true)
            #expect(PostHogStackTraceProcessor.isInApp(module: "com.other", config: config) == false)
        }

        @Test("uses prefix matching for excludes")
        func usesPrefixMatchingForExcludes() {
            let config = PostHogErrorTrackingConfig()
            config.inAppExcludes = ["Firebase"]

            #expect(PostHogStackTraceProcessor.isInApp(module: "FirebaseCore", config: config) == false)
            #expect(PostHogStackTraceProcessor.isInApp(module: "FirebaseAnalytics", config: config) == false)
        }
    }

    // MARK: - Stack Trace Capture Tests

    @Suite("Stack Trace Capture")
    struct StackTraceCaptureTests {
        @Test("captures current stack trace")
        func capturesCurrentStackTrace() {
            let config = PostHogErrorTrackingConfig()
            let frames = PostHogStackTraceProcessor.captureCurrentStackTraceWithMetadata(config: config)

            #expect(frames.count > 0)
        }

        @Test("captured frames have instruction addresses")
        func framesHaveInstructionAddresses() {
            let config = PostHogErrorTrackingConfig()
            let frames = PostHogStackTraceProcessor.captureCurrentStackTraceWithMetadata(config: config)

            for frame in frames {
                #expect(frame.instructionAddress > 0)
            }
        }

        @Test("captured frames have module info")
        func framesHaveModuleInfo() {
            let config = PostHogErrorTrackingConfig()
            let frames = PostHogStackTraceProcessor.captureCurrentStackTraceWithMetadata(config: config)

            let framesWithModule = frames.filter { $0.module != nil }
            #expect(framesWithModule.count > 0)
        }

        @Test("strips PostHog frames from top of stack")
        func stripsPostHogFrames() {
            let config = PostHogErrorTrackingConfig()
            let frames = PostHogStackTraceProcessor.captureCurrentStackTraceWithMetadata(config: config)

            let topFrame = frames.first
            #expect(topFrame?.module != "PostHog")
        }
    }

    // MARK: - Symbolicate Addresses Tests

    @Suite("Symbolicate Addresses")
    struct SymbolicateAddressesTests {
        @Test("symbolicates array of addresses")
        func symbolicatesAddresses() {
            let config = PostHogErrorTrackingConfig()
            let addresses = Thread.callStackReturnAddresses

            let frames = PostHogStackTraceProcessor.symbolicateAddresses(
                addresses,
                config: config,
                stripTopPostHogFrames: false
            )

            #expect(frames.count > 0)
        }

        @Test("respects stripTopPostHogFrames parameter")
        func respectsStripParameter() {
            let config = PostHogErrorTrackingConfig()
            let addresses = Thread.callStackReturnAddresses

            let framesWithStrip = PostHogStackTraceProcessor.symbolicateAddresses(
                addresses,
                config: config,
                stripTopPostHogFrames: true
            )

            let framesWithoutStrip = PostHogStackTraceProcessor.symbolicateAddresses(
                addresses,
                config: config,
                stripTopPostHogFrames: false
            )

            #expect(framesWithStrip.count <= framesWithoutStrip.count)
        }
    }

    // MARK: - Frame Dictionary Tests

    @Suite("Frame Dictionary Conversion")
    struct FrameDictionaryTests {
        @Test("converts frame to dictionary with required fields")
        func convertsToDictionaryWithRequiredFields() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x100_0000,
                module: "TestModule",
                package: "/path/to/TestModule",
                imageAddress: 0x100_0000,
                inApp: true,
                function: "testFunction",
                symbolAddress: 0x100_0000
            )

            let dict = frame.toDictionary

            #expect(dict["instruction_addr"] as? String == "0x1000000")
            #expect(dict["platform"] as? String == "apple")
            #expect(dict["in_app"] as? Bool == true)
            #expect(dict["module"] as? String == "TestModule")
            #expect(dict["package"] as? String == "/path/to/TestModule")
            #expect(dict["function"] as? String == "testFunction")
        }

        @Test("omits nil fields from dictionary")
        func omitsNilFields() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x100_0000,
                module: nil,
                package: nil,
                imageAddress: nil,
                inApp: false,
                function: nil,
                symbolAddress: nil
            )

            let dict = frame.toDictionary

            #expect(dict["instruction_addr"] != nil)
            #expect(dict["platform"] != nil)
            #expect(dict["in_app"] != nil)
            #expect(dict["module"] == nil)
            #expect(dict["package"] == nil)
            #expect(dict["function"] == nil)
            #expect(dict["image_addr"] == nil)
            #expect(dict["symbol_addr"] == nil)
        }

        @Test("formats addresses as hex strings")
        func formatsAddressesAsHex() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x7FFF_1234_5678,
                module: "Test",
                package: nil,
                imageAddress: 0x7FFF_0000_0000,
                inApp: true,
                function: nil,
                symbolAddress: 0x7FFF_1234_5000
            )

            let dict = frame.toDictionary

            #expect((dict["instruction_addr"] as? String)?.hasPrefix("0x") == true)
            #expect((dict["image_addr"] as? String)?.hasPrefix("0x") == true)
            #expect((dict["symbol_addr"] as? String)?.hasPrefix("0x") == true)
        }
    }
}
