//
//  PostHogErrorTrackingIgnoredTypesTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

// Regression coverage for https://github.com/PostHog/posthog-ios/issues/653.
// React Native rethrows fatal JS errors as `NSException(name: "RCTFatalException")`,
// which the iOS crash reporter captures as a separate native crash —
// duplicating the event the JS layer already captured with its own stack
// trace. Adding `RCTFatalException` to
// `errorTrackingConfig.ignoredExceptionTypes` must cause that crash report
// to be skipped at the autocapture layer.
#if os(iOS) || os(macOS) || os(tvOS)

    @Suite("ErrorTracking ignoredExceptionTypes")
    struct ErrorTrackingIgnoredTypesTest {
        @Test("returns false when ignoredExceptionTypes is empty")
        func emptyIgnoredListPassesAllExceptions() {
            let properties: [String: Any] = [
                "$exception_list": [["type": "RCTFatalException", "value": "boom"]],
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(properties, ignoredTypes: []) == false
            )
        }

        @Test("matches when outer exception type is in ignored list")
        func outerTypeMatchSuppresses() {
            let properties: [String: Any] = [
                "$exception_list": [["type": "RCTFatalException", "value": "boom"]],
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        properties,
                        ignoredTypes: ["RCTFatalException"]
                    ) == true
            )
        }

        @Test("matches when an underlying exception in the chain is in the ignored list")
        func underlyingTypeMatchSuppresses() {
            // PHPLCrashReportExceptionInfo doesn't currently expose
            // `userInfo`, but for non-crash report paths the SDK builds a
            // multi-entry `$exception_list` walking `NSUnderlyingErrorKey`
            // (see `PostHogExceptionProcessor.buildExceptionList`). Make
            // sure a wrapped RCTFatalException is still suppressed when
            // it's not the outermost entry.
            let properties: [String: Any] = [
                "$exception_list": [
                    ["type": "NSException", "value": "wrapper"],
                    ["type": "RCTFatalException", "value": "boom"],
                ],
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        properties,
                        ignoredTypes: ["RCTFatalException"]
                    ) == true
            )
        }

        @Test("does not match exceptions whose type isn't in the ignored list")
        func nonMatchPassesThrough() {
            let properties: [String: Any] = [
                "$exception_list": [["type": "NSGenericException", "value": "boom"]],
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        properties,
                        ignoredTypes: ["RCTFatalException"]
                    ) == false
            )
        }

        @Test("returns false when properties has no $exception_list key")
        func missingExceptionListReturnsFalse() {
            let properties: [String: Any] = [
                "$exception_level": "fatal",
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        properties,
                        ignoredTypes: ["RCTFatalException"]
                    ) == false
            )
        }

        @Test("returns false when $exception_list is empty")
        func emptyExceptionListReturnsFalse() {
            let properties: [String: Any] = [
                "$exception_list": [[String: Any]](),
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        properties,
                        ignoredTypes: ["RCTFatalException"]
                    ) == false
            )
        }

        @Test("match is exact and case-sensitive (NSException class names are stable identifiers)")
        func caseSensitiveMatch() {
            let properties: [String: Any] = [
                "$exception_list": [["type": "RCTFatalException", "value": "boom"]],
            ]
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        properties,
                        ignoredTypes: ["rctfatalexception"]
                    ) == false
            )
        }

        @Test("config field default is empty so callers see no behavior change")
        func defaultIsEmpty() {
            let config = PostHogErrorTrackingConfig()
            #expect(config.ignoredExceptionTypes.isEmpty)
        }
    }

#endif
