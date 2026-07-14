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
        /// `(properties, ignoredTypes, expected)` — drives every case the
        /// matcher needs to handle. Adding a row covers a new shape without
        /// duplicating the assertion boilerplate.
        struct MatchCase {
            let label: String
            let properties: [String: AnyHashable]
            let ignoredTypes: [String]
            let expected: Bool
        }

        static let matchCases: [MatchCase] = [
            MatchCase(
                label: "empty ignored list never matches",
                properties: ["$exception_list": [["type": "RCTFatalException", "value": "boom"]]],
                ignoredTypes: [],
                expected: false
            ),
            MatchCase(
                label: "outer type in ignored list matches",
                properties: ["$exception_list": [["type": "RCTFatalException", "value": "boom"]]],
                ignoredTypes: ["RCTFatalException"],
                expected: true
            ),
            MatchCase(
                label: "underlying type anywhere in chain matches",
                // PHPLCrashReportExceptionInfo doesn't currently expose
                // `userInfo`, but for non-crash report paths the SDK builds
                // a multi-entry `$exception_list` walking `NSUnderlyingErrorKey`
                // (see `PostHogExceptionProcessor.buildExceptionList`). Make
                // sure a wrapped RCTFatalException is still suppressed when
                // it's not the outermost entry.
                properties: [
                    "$exception_list": [
                        ["type": "NSException", "value": "wrapper"],
                        ["type": "RCTFatalException", "value": "boom"],
                    ],
                ],
                ignoredTypes: ["RCTFatalException"],
                expected: true
            ),
            MatchCase(
                label: "type not in list passes through",
                properties: ["$exception_list": [["type": "NSGenericException", "value": "boom"]]],
                ignoredTypes: ["RCTFatalException"],
                expected: false
            ),
            MatchCase(
                label: "missing $exception_list key returns false",
                properties: ["$exception_level": "fatal"],
                ignoredTypes: ["RCTFatalException"],
                expected: false
            ),
            MatchCase(
                label: "empty $exception_list returns false",
                properties: ["$exception_list": [[String: AnyHashable]]()],
                ignoredTypes: ["RCTFatalException"],
                expected: false
            ),
            MatchCase(
                label: "match is case-sensitive (NSException class names are stable identifiers)",
                properties: ["$exception_list": [["type": "RCTFatalException", "value": "boom"]]],
                ignoredTypes: ["rctfatalexception"],
                expected: false
            ),
        ]

        @Test("exceptionListMatchesIgnoredTypes", arguments: matchCases)
        func exceptionListMatcher(_ matchCase: MatchCase) {
            #expect(
                PostHogErrorTrackingAutoCaptureIntegration
                    .exceptionListMatchesIgnoredTypes(
                        matchCase.properties as [String: Any],
                        ignoredTypes: matchCase.ignoredTypes
                    ) == matchCase.expected,
                "case '\(matchCase.label)' expected \(matchCase.expected)"
            )
        }

        @Test("config field defaults to RCTFatalException so React Native apps get dedup out of the box")
        func defaultIsRCTFatalException() {
            let config = PostHogErrorTrackingConfig()
            #expect(config.ignoredExceptionTypes == ["RCTFatalException"])
        }
    }

    @Suite("ErrorTracking ignoredExceptionTypes capture paths", .serialized)
    class ErrorTrackingIgnoredTypesCaptureTest {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer(version: 4)
            server.start()
        }

        deinit {
            server.stop()
        }

        private enum TestError: Error {
            case boom
        }

        private func getSut(ignoredExceptionTypes: [String]? = nil) -> PostHogSDK {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.flushAt = 1
            config.captureApplicationLifecycleEvents = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            if let ignoredExceptionTypes {
                config.errorTrackingConfig.ignoredExceptionTypes = ignoredExceptionTypes
            }

            let storage = PostHogStorage(config)
            storage.reset()

            return PostHogSDK.with(config)
        }

        @Test("generic capture drops $exception whose list contains an ignored type")
        func genericCaptureDropsIgnoredType() {
            let sut = getSut()

            sut.capture("$exception", properties: ["$exception_list": [["type": "RCTFatalException", "value": "boom"]]])
            sut.capture("marker")

            let events = getBatchedEvents(server)
            #expect(events.filter { $0.event == "$exception" }.isEmpty)
            #expect(events.contains { $0.event == "marker" })

            sut.reset()
            sut.close()
        }

        @Test("generic capture keeps $exception whose list has no ignored type")
        func genericCaptureKeepsOtherTypes() {
            let sut = getSut()

            sut.capture("$exception", properties: ["$exception_list": [["type": "SomeOtherError", "value": "boom"]]])

            let events = getBatchedEvents(server).filter { $0.event == "$exception" }
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("captureException still drops ignored types after the gate moved to captureInternal")
        func captureExceptionStillDropsIgnoredType() {
            let sut = getSut(ignoredExceptionTypes: ["TestError"])

            sut.captureException(TestError.boom)
            sut.capture("marker")

            let events = getBatchedEvents(server)
            #expect(events.filter { $0.event == "$exception" }.isEmpty)
            #expect(events.contains { $0.event == "marker" })

            sut.reset()
            sut.close()
        }
    }

#endif
