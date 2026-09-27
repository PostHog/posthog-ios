import Foundation
@testable import PostHog
import Testing

#if os(iOS) && !targetEnvironment(macCatalyst) && compiler(>=6.4)
    import MetricKit

    @Suite("Memory exception reporter (iOS 27)", .serialized)
    class PostHogMemoryExceptionReporterTest {
        static let killedPid: Int32 = 4242
        static let appUUID = "11111111-2222-3333-4444-555555555555"
        static let libUUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

        let server: MockPostHogServer
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("oom-\(UUID().uuidString)")

        init() {
            server = MockPostHogServer(version: 4)
            server.start()
        }

        deinit {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        private func getSut() -> PostHogSDK {
            // A token per test gives each its own storage: `reset()` doesn't clear the persisted event queue.
            let config = PostHogConfig(projectToken: "\(testProjectToken)_\(UUID().uuidString)", host: "http://localhost:9001")
            config.flushAt = 1
            config.captureApplicationLifecycleEvents = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.errorTrackingConfig.inAppIncludes = ["MyApp"]
            config.errorTrackingConfig.inAppByDefault = false
            PostHogStorage(config).reset()
            return PostHogSDK.with(config)
        }

        /// A report in the JSON shape `DiagnosticReport` decodes, as worked out against the
        /// iOS 27.2 SDK. MetricKit has no public initializer for it. The stack is innermost
        /// first: malloc, called by the app.
        private static func reportJSON(end: Date) -> Data {
            let json: [String: Any] = [
                "timeRange": [
                    "begin": end.addingTimeInterval(-3600).timeIntervalSinceReferenceDate,
                    "end": end.timeIntervalSinceReferenceDate,
                ],
                "environment": [
                    "pid": killedPid,
                    "regionFormat": "US",
                    "osVersion": ["platform": "iOS", "number": "27.0", "buildNumber": "24A1"],
                    "deviceType": "iPhone18,1",
                    "platformArchitecture": "arm64e",
                    "lowPowerModeEnabled": false,
                    "isTestFlightApp": false,
                    "applicationVersion": "9.9",
                    "applicationBuildVersion": "99",
                    "bundleIdentifier": "com.example.MyApp",
                    "signpostData": [],
                    "states": [String: Any](),
                ],
                "memoryExceptionDiagnostic": [
                    "callStackTree": [
                        "callStackPerThread": true,
                        "binaryInfo": [
                            ["uuid": appUUID, "name": "MyApp"],
                            ["uuid": libUUID, "name": "libsystem_malloc.dylib"],
                        ],
                        "callStackThreads": [[
                            "threadAttributed": true,
                            "rootFrames": [[
                                "binaryUUID": libUUID,
                                "address": 0x1_8000_1234,
                                "offsetIntoBinaryTextSegment": 0x1234,
                                "sampleCount": 1,
                                "subFrames": [[
                                    "binaryUUID": appUUID,
                                    "address": 0x1_0000_0500,
                                    "offsetIntoBinaryTextSegment": 0x500,
                                    "sampleCount": 1,
                                    "subFrames": [],
                                ]],
                            ]],
                        ]],
                    ],
                ],
            ]
            return try! JSONSerialization.data(withJSONObject: json)
        }

        @Test("captures an OutOfMemory $exception in the killed process's session")
        func capturesInKilledSession() throws {
            guard #available(iOS 27.0, *) else { return }
            let sut = getSut()
            let store = PostHogProcessContextStore(directory: directory, currentPid: Self.killedPid)
            store.write(try JSONSerialization.data(withJSONObject: [
                "distinct_id": "killed-user",
                "event_properties": ["$session_id": "killed-session", "$app_version": "9.9"],
                PostHogExceptionStepFields.stepsKey: [[PostHogExceptionStepFields.message: "opened gallery"]],
            ]))

            let report = try JSONDecoder().decode(DiagnosticReport.self, from: Self.reportJSON(end: Date().addingTimeInterval(60)))
            guard case let .memoryException(diagnostic) = report.result else {
                Issue.record("expected a memory exception, got \(report.result)")
                return
            }
            PostHogMemoryExceptionReporter(postHog: sut, contextStore: store).capture(diagnostic, report: report)

            let event = try #require(getBatchedEvents(server).first { $0.event == "$exception" })
            #expect(event.distinctId == "killed-user")
            #expect(event.properties["$session_id"] as? String == "killed-session")
            #expect(event.properties["$exception_level"] as? String == "fatal")

            let steps = event.properties[PostHogExceptionStepFields.stepsKey] as? [[String: Any]]
            #expect(steps?.first?[PostHogExceptionStepFields.message] as? String == "opened gallery")

            let exception = try #require((event.properties["$exception_list"] as? [[String: Any]])?.first)
            #expect(exception["type"] as? String == "OutOfMemory")
            let frames = try #require((exception["stacktrace"] as? [String: Any])?["frames"] as? [[String: Any]])
            #expect(frames.map { $0["module"] as? String } == ["MyApp", "libsystem_malloc.dylib"])
            #expect(frames.map { $0["image_addr"] as? String } == ["0x0000000100000000", "0x0000000180000000"])
            #expect(frames.map { $0["in_app"] as? Bool } == [true, false])

            let images = try #require(event.properties["$debug_images"] as? [[String: Any]])
            #expect(Set(images.compactMap { $0["debug_id"] as? String }) == [Self.appUUID, Self.libUUID])

            sut.reset()
            sut.close()
        }

        @Test("without a saved context, still captures with device, SDK and app version properties")
        func capturesWithoutContext() throws {
            guard #available(iOS 27.0, *) else { return }
            let sut = getSut()
            let store = PostHogProcessContextStore(directory: directory, currentPid: 1)

            let report = try JSONDecoder().decode(DiagnosticReport.self, from: Self.reportJSON(end: Date()))
            guard case let .memoryException(diagnostic) = report.result else {
                Issue.record("expected a memory exception")
                return
            }
            PostHogMemoryExceptionReporter(postHog: sut, contextStore: store).capture(diagnostic, report: report)

            let event = try #require(getBatchedEvents(server).first { $0.event == "$exception" })
            #expect(event.properties["$app_version"] as? String == "9.9")
            #expect(event.properties["$app_build"] as? String == "99")
            #expect(event.properties["$lib"] as? String == postHogSdkName)
            #expect(event.properties["$lib_version"] as? String == postHogVersion)
            #expect(event.properties["$os_name"] != nil)
            #expect(event.properties["$session_id"] == nil)

            sut.reset()
            sut.close()
        }
    }
#endif
