//
//  PostHogExceptionProcessorTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 22/12/2025.
//

import Foundation
import Testing

@testable import PostHog

@Suite("PostHogExceptionProcessor Tests")
struct PostHogExceptionProcessorTest {
    let config = PostHogErrorTrackingConfig()

    // MARK: - Error to Properties Tests

    @Suite("Error to Properties")
    struct ErrorToPropertiesTests {
        let config = PostHogErrorTrackingConfig()

        @Test("converts simple Swift error to properties")
        func convertsSimpleSwiftError() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            #expect(properties["$exception_level"] as? String == "error")

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            #expect(exceptionList != nil)
            #expect(exceptionList?.count == 1)

            let exception = exceptionList?.first
            #expect(exception?["type"] as? String == "TestSwiftError")
            #expect(exception?["thread_id"] as? Int != nil)

            let mechanism = exception?["mechanism"] as? [String: Any]
            #expect(mechanism?["type"] as? String == "generic")
            #expect(mechanism?["handled"] as? Bool == true)
            #expect(mechanism?["synthetic"] as? Bool == true)

            let stacktrace = exception?["stacktrace"] as? [String: Any]
            #expect(stacktrace != nil)
            #expect(stacktrace?["type"] as? String == "raw")
        }

        @Test("converts NSError to properties with domain as type")
        func convertsNSErrorWithDomain() {
            let error = NSError(
                domain: "com.posthog.TestDomain",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Test error message"]
            )
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: false,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let exception = exceptionList?.first

            #expect(exception?["type"] as? String == "com.posthog.TestDomain")
            #expect((exception?["value"] as? String)?.contains("Test error message") == true)
            #expect((exception?["value"] as? String)?.contains("500") == true)

            let mechanism = exception?["mechanism"] as? [String: Any]
            #expect(mechanism?["handled"] as? Bool == false)
        }

        @Test("walks error chain via NSUnderlyingErrorKey")
        func walksErrorChain() {
            let rootError = NSError(
                domain: "RootDomain",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Root cause"]
            )
            let wrapperError = NSError(
                domain: "WrapperDomain",
                code: 200,
                userInfo: [
                    NSLocalizedDescriptionKey: "Wrapper error",
                    NSUnderlyingErrorKey: rootError,
                ]
            )

            let properties = PostHogExceptionProcessor.errorToProperties(
                wrapperError,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            #expect(exceptionList?.count == 2)

            #expect(exceptionList?[0]["type"] as? String == "WrapperDomain")
            #expect(exceptionList?[1]["type"] as? String == "RootDomain")
        }

        @Test("handles circular error references")
        func handlesCircularReferences() {
            let error1 = NSError(domain: "Domain1", code: 1, userInfo: nil)
            let error2 = NSError(domain: "Domain2", code: 2, userInfo: [NSUnderlyingErrorKey: error1])

            let properties = PostHogExceptionProcessor.errorToProperties(
                error2,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            #expect(exceptionList != nil)
            #expect(exceptionList!.count <= 2)
        }

        @Test("uses custom mechanism type")
        func usesCustomMechanismType() {
            let error = TestSwiftError.validationError(field: "email")
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                mechanismType: "custom_handler",
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let mechanism = exceptionList?.first?["mechanism"] as? [String: Any]
            #expect(mechanism?["type"] as? String == "custom_handler")
        }

        @Test("extracts module from error domain")
        func extractsModuleFromDomain() {
            let error = TestSwiftError.networkError(code: 500)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let exception = exceptionList?.first
            #expect(exception?["module"] as? String != nil)
        }
    }

    // MARK: - NSException to Properties Tests

    @Suite("NSException to Properties")
    struct NSExceptionToPropertiesTests {
        let config = PostHogErrorTrackingConfig()

        @Test("converts NSException to properties")
        func convertsNSException() {
            let exception = NSException(
                name: NSExceptionName("TestException"),
                reason: "Test exception reason",
                userInfo: nil
            )

            let properties = PostHogExceptionProcessor.exceptionToProperties(
                exception,
                handled: true,
                config: config
            )

            #expect(properties["$exception_level"] as? String == "error")

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            #expect(exceptionList?.count == 1)

            let exc = exceptionList?.first
            #expect(exc?["type"] as? String == "TestException")
            #expect(exc?["value"] as? String == "Test exception reason")
        }

        @Test("handles NSException without reason")
        func handlesExceptionWithoutReason() {
            let exception = NSException(
                name: NSExceptionName("NoReasonException"),
                reason: nil,
                userInfo: nil
            )

            let properties = PostHogExceptionProcessor.exceptionToProperties(
                exception,
                handled: false,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let exc = exceptionList?.first
            #expect(exc?["type"] as? String == "NoReasonException")
            #expect(exc?["value"] == nil)
        }

        @Test("marks exception as unhandled")
        func marksUnhandled() {
            let exception = NSException(
                name: .genericException,
                reason: "Unhandled",
                userInfo: nil
            )

            let properties = PostHogExceptionProcessor.exceptionToProperties(
                exception,
                handled: false,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let mechanism = exceptionList?.first?["mechanism"] as? [String: Any]
            #expect(mechanism?["handled"] as? Bool == false)
        }
    }

    // MARK: - Message to Properties Tests

    @Suite("Message to Properties")
    struct MessageToPropertiesTests {
        let config = PostHogErrorTrackingConfig()

        @Test("converts message string to properties")
        func convertsMessageString() {
            let message = "Something went wrong"
            let properties = PostHogExceptionProcessor.messageToProperties(
                message,
                config: config
            )

            #expect(properties["$exception_level"] as? String == "error")

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            #expect(exceptionList?.count == 1)

            let exception = exceptionList?.first
            #expect(exception?["type"] as? String == "Message")
            #expect(exception?["value"] as? String == "Something went wrong")
        }

        @Test("message exceptions are always synthetic and handled")
        func messageExceptionsAreSyntheticAndHandled() {
            let properties = PostHogExceptionProcessor.messageToProperties(
                "Test message",
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let mechanism = exceptionList?.first?["mechanism"] as? [String: Any]
            #expect(mechanism?["synthetic"] as? Bool == true)
            #expect(mechanism?["handled"] as? Bool == true)
        }

        @Test("message uses custom mechanism type")
        func usesCustomMechanismType() {
            let properties = PostHogExceptionProcessor.messageToProperties(
                "Test",
                mechanismType: "custom",
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let mechanism = exceptionList?.first?["mechanism"] as? [String: Any]
            #expect(mechanism?["type"] as? String == "custom")
        }
    }

    // MARK: - Debug Images Tests

    @Suite("Debug Images")
    struct DebugImagesTests {
        let config = PostHogErrorTrackingConfig()

        @Test("attaches debug images to error properties")
        func attachesDebugImages() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let debugImages = properties["$debug_images"] as? [[String: Any]]
            #expect(debugImages != nil)
            #expect(debugImages!.count > 0)

            let image = debugImages?.first
            #expect(image?["type"] as? String == "macho")
            #expect(image?["code_file"] as? String != nil)
            #expect(image?["image_addr"] as? String != nil)
            #expect(image?["image_size"] as? UInt64 != nil)
        }

        @Test("debug images have valid UUID format")
        func debugImagesHaveValidUUID() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let debugImages = properties["$debug_images"] as? [[String: Any]]
            let imageWithUUID = debugImages?.first { $0["debug_id"] != nil }

            if let uuid = imageWithUUID?["debug_id"] as? String {
                let uuidPattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
                let regex = try? NSRegularExpression(pattern: uuidPattern)
                let range = NSRange(uuid.startIndex..., in: uuid)
                #expect(regex?.firstMatch(in: uuid, range: range) != nil)
            }
        }
    }

    // MARK: - Stack Trace Tests

    @Suite("Stack Trace")
    struct StackTraceTests {
        let config = PostHogErrorTrackingConfig()

        @Test("stack trace has raw type")
        func stackTraceHasRawType() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let stacktrace = exceptionList?.first?["stacktrace"] as? [String: Any]
            #expect(stacktrace?["type"] as? String == "raw")
        }

        @Test("stack trace contains frames")
        func stackTraceContainsFrames() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let stacktrace = exceptionList?.first?["stacktrace"] as? [String: Any]
            let frames = stacktrace?["frames"] as? [[String: Any]]

            #expect(frames != nil)
            #expect(frames!.count > 0)
        }

        @Test("frames have required fields")
        func framesHaveRequiredFields() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let stacktrace = exceptionList?.first?["stacktrace"] as? [String: Any]
            let frames = stacktrace?["frames"] as? [[String: Any]]
            let frame = frames?.first

            #expect(frame?["instruction_addr"] as? String != nil)
            #expect(frame?["platform"] as? String == "apple")
            #expect(frame?["in_app"] as? Bool != nil)
        }

        @Test("frames have hex address format")
        func framesHaveHexAddressFormat() {
            let error = TestSwiftError.networkError(code: 404)
            let properties = PostHogExceptionProcessor.errorToProperties(
                error,
                handled: true,
                config: config
            )

            let exceptionList = properties["$exception_list"] as? [[String: Any]]
            let stacktrace = exceptionList?.first?["stacktrace"] as? [String: Any]
            let frames = stacktrace?["frames"] as? [[String: Any]]
            let instructionAddr = frames?.first?["instruction_addr"] as? String

            #expect(instructionAddr?.hasPrefix("0x") == true)
        }
    }
}

// MARK: - Test Helpers

enum TestSwiftError: Error {
    case networkError(code: Int)
    case validationError(field: String)
    case unknownError
}
