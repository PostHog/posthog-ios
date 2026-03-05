//
//  PostHogCrashReportProcessorTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 22/12/2025.
//

import Foundation
@_spi(Experimental) @testable import PostHog
import Testing

#if os(iOS) || os(macOS) || os(tvOS)
    import CrashReporter

    @Suite("PostHogCrashReportProcessor Tests")
    struct PostHogCrashReportProcessorTest {
        // MARK: - Live Report Tests

        @Suite("Process Live Report")
        struct ProcessLiveReportTests {
            let config = PostHogErrorTrackingConfig()

            @Test("processes live crash report")
            func processesLiveCrashReport() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                #expect(properties["$exception_level"] as? String == "fatal")
                #expect(properties["$exception_list"] != nil)
            }

            @Test("live report contains exception list")
            func liveReportContainsExceptionList() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                #expect(exceptionList != nil)
                #expect(exceptionList!.count > 0)
            }

            @Test("live report exception has type and mechanism")
            func liveReportExceptionHasTypeAndMechanism() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                let exception = exceptionList?.first

                #expect(exception?["type"] != nil)

                let mechanism = exception?["mechanism"] as? [String: Any]
                #expect(mechanism != nil)
                let mechHandled = mechanism?["handled"] as? Bool
                #expect(mechHandled == false)
                let mechSynthetic = mechanism?["synthetic"] as? Bool
                #expect(mechSynthetic == false)
            }

            @Test("live report contains stack trace")
            func liveReportContainsStackTrace() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                let exception = exceptionList?.first
                let stacktrace = exception?["stacktrace"] as? [String: Any]

                #expect(stacktrace != nil)
                let stType = stacktrace?["type"] as? String
                #expect(stType == "raw")

                let frames = stacktrace?["frames"] as? [[String: Any]]
                #expect(frames != nil)
                #expect(frames!.count > 0)
            }

            @Test("live report frames have instruction addresses")
            func liveReportFramesHaveInstructionAddresses() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                let exc = exceptionList?.first
                let stacktrace = exc?["stacktrace"] as? [String: Any]
                let frames = stacktrace?["frames"] as? [[String: Any]]

                for frame in frames ?? [] {
                    let addr = frame["instruction_addr"] as? String
                    #expect(addr != nil)
                    #expect(addr?.hasPrefix("0x") == true)
                }
            }

            @Test("live report contains debug images")
            func liveReportContainsDebugImages() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let debugImages = properties["$debug_images"] as? [[String: Any]]
                #expect(debugImages != nil)
                #expect(debugImages!.count > 0)
            }

            @Test("debug images have required fields")
            func debugImagesHaveRequiredFields() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let debugImages = properties["$debug_images"] as? [[String: Any]]
                let image = debugImages?.first

                let imgType = image?["type"] as? String
                #expect(imgType == "macho")
                let codeFile = image?["code_file"] as? String
                #expect(codeFile != nil)
                let imageAddr = image?["image_addr"] as? String
                #expect(imageAddr != nil)
                let imageSize = image?["image_size"] as? UInt64
                #expect(imageSize != nil)
            }
        }

        // MARK: - Crash Timestamp Tests

        @Suite("Crash Timestamp")
        struct CrashTimestampTests {
            @Test("extracts crash timestamp from report")
            func extractsCrashTimestamp() throws {
                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let timestamp = PostHogCrashReportProcessor.getCrashTimestamp(report)

                #expect(timestamp != nil)
                #expect(timestamp!.timeIntervalSinceNow < 60)
                #expect(timestamp!.timeIntervalSinceNow > -60)
            }
        }

        // MARK: - In-App Detection Tests

        @Suite("In-App Detection")
        struct InAppDetectionTests {
            @Test("marks frames as in-app based on config")
            func marksFramesAsInApp() throws {
                let config = PostHogErrorTrackingConfig()
                config.inAppIncludes = ["xctest"]

                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                let exc = exceptionList?.first
                let stacktrace = exc?["stacktrace"] as? [String: Any]
                let frames = stacktrace?["frames"] as? [[String: Any]]

                let inAppFrames = frames?.filter { $0["in_app"] as? Bool == true }
                #expect(inAppFrames != nil)
            }

            @Test("marks system frames as not in-app")
            func marksSystemFramesAsNotInApp() throws {
                let config = PostHogErrorTrackingConfig()

                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                let exc = exceptionList?.first
                let stacktrace = exc?["stacktrace"] as? [String: Any]
                let frames = stacktrace?["frames"] as? [[String: Any]]

                let systemFrames = frames?.filter { frame in
                    let module = frame["module"] as? String ?? ""
                    return module.hasPrefix("libsystem") || module == "Foundation"
                }

                for frame in systemFrames ?? [] {
                    let inApp = frame["in_app"] as? Bool
                    #expect(inApp == false)
                }
            }
        }

        // MARK: - Thread ID Tests

        @Suite("Thread ID")
        struct ThreadIDTests {
            @Test("exception has thread ID")
            func exceptionHasThreadId() throws {
                let config = PostHogErrorTrackingConfig()

                let reporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())
                guard let reporter else {
                    Issue.record("Failed to create PLCrashReporter")
                    return
                }

                let reportData = try reporter.generateLiveReportAndReturnError()
                let report = try PLCrashReport(data: reportData)

                let properties = PostHogCrashReportProcessor.processReport(report, config: config)

                let exceptionList = properties["$exception_list"] as? [[String: Any]]
                let exception = exceptionList?.first

                #expect(exception?["thread_id"] != nil)
            }
        }
    }
#endif
