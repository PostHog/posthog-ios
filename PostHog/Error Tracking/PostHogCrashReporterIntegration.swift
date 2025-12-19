//
//  PostHogCrashReporterIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/12/2025.
//

import Foundation

#if os(iOS) || os(macOS) || os(tvOS)
    import CrashReporter

    class PostHogCrashReporterIntegration: PostHogIntegration {
        private static let integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        var requiresSwizzling: Bool { false }

        private weak var postHog: PostHogSDK?
        private var crashReporter: PLCrashReporter?

        func install(_ postHog: PostHogSDK) throws {
            try PostHogCrashReporterIntegration.integrationInstalledLock.withLock {
                if PostHogCrashReporterIntegration.integrationInstalled {
                    throw InternalPostHogError(description: "Crash report integration already installed to another PostHogSDK instance.")
                }
                PostHogCrashReporterIntegration.integrationInstalled = true
            }

            self.postHog = postHog
            if let crashReporter = setupCrashReporter() {
                self.crashReporter = crashReporter
                // Note: Order here matters, we need to process any pending crash report before enabling the crash reporter
                processPendingCrashReportIfNeeded(reporter: crashReporter)
                enableCrashReporter(reporter: crashReporter)
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            if self.postHog === postHog || self.postHog == nil {
                stop()
                crashReporter = nil
                self.postHog = nil
                PostHogCrashReporterIntegration.integrationInstalledLock.withLock {
                    PostHogCrashReporterIntegration.integrationInstalled = false
                }
            }
        }

        func start() {
            // No-op for crash reporting. Always active once installed
        }

        func stop() {
            // No-op for crash reporting. Always active once installed
        }

        func contextDidChange(_ context: [String: Any]) {
            guard let crashReporter else { return }

            // Serialize context to JSON and set as customData
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: context, options: [])
                crashReporter.customData = jsonData
            } catch {
                hedgeLog("Failed to serialize crash context: \(error)")
            }
        }

        // MARK: - Private Methods

        private func setupCrashReporter() -> PLCrashReporter? {
            // Check for debugger - crash handler won't work when debugging
            if PostHogDebugUtils.isDebuggerAttached() {
                hedgeLog("Crash handler is disabled because a debugger is attached. Crashes will be caught by the debugger instead.")
                return nil
            }

            // Configure PLCrashReporter
            let config = PLCrashReporterConfig(
                signalHandlerType: .mach,
                symbolicationStrategy: [], // No local symbolication, we'll be doing server-side
                shouldRegisterUncaughtExceptionHandler: true
            )

            guard let reporter = PLCrashReporter(configuration: config) else {
                hedgeLog("Failed to create PLCrashReporter instance")
                return nil
            }

            return reporter
        }

        private func processPendingCrashReportIfNeeded(reporter: PLCrashReporter) {
            // Check for pending crash report FIRST (before enabling for new crashes)
            if reporter.hasPendingCrashReport() {
                hedgeLog("Found pending crash report, processing...")
                processPendingCrashReport()
            }
        }

        private func enableCrashReporter(reporter: PLCrashReporter) {
            // Enable crash reporter for this session
            do {
                try reporter.enableAndReturnError()
                hedgeLog("PLCrashReporter enabled successfully")
            } catch {
                hedgeLog("Failed to enable PLCrashReporter: \(error)")
            }
        }

        private func processPendingCrashReport() {
            guard let crashReporter, let postHog else {
                return
            }

            do {
                let crashData = try crashReporter.loadPendingCrashReportDataAndReturnError()
                let crashReport = try PLCrashReport(data: crashData)

                // Extract saved context from crash report's customData
                var savedContext: [String: Any] = [:]
                if let customData = crashReport.customData {
                    savedContext = (try? JSONSerialization.jsonObject(with: customData, options: [])) as? [String: Any] ?? [:]
                }

                // Extract identity and event properties from saved context
                let crashDistinctId = savedContext["distinct_id"] as? String ?? postHog.getDistinctId()
                let crashEventProperties = savedContext["event_properties"] as? [String: Any] ?? [:]

                // Collect crash-specific event properties (stack traces, exceptions etc)
                let exceptionProperties = PostHogCrashReportProcessor.processReport(crashReport, config: postHog.config.errorTrackingConfig)

                // Merge: crash-time event properties as base, exception properties on top
                let finalProperties = crashEventProperties.merging(exceptionProperties) { _, new in new }

                // Collect crash timestamp
                let crashTimestamp = PostHogCrashReportProcessor.getCrashTimestamp(crashReport)

                // Capture using internal method and bypass buildProperties
                postHog.captureInternal(
                    "$exception",
                    distinctId: crashDistinctId,
                    properties: finalProperties,
                    timestamp: crashTimestamp,
                    skipBuildProperties: true
                )

                hedgeLog("Crash report processed and captured")
            } catch {
                // Best effort for now.
                // We log and ignore and let the crash report be purged.
                // - On a new crash, old report will be overwritten anyway
                // - Keeping the report around could risk infinite retry loop until next crash if it's corrupt
                //
                // Note: This could fail because of a transient error though, in the future we could check the returned error
                //       and only purge if PLCrashReporterErrorCrashReportInvalid, then keep the report around for max X retries
                hedgeLog("Failed to process crash report: \(error)")
            }

            // Always purge the crash report after processing
            crashReporter.purgePendingCrashReport()
        }
    }

#else
    // watchOS stub - crash reporting is not available
    class PostHogCrashReporterIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { false }

        func install(_: PostHogSDK) throws {
            hedgeLog("Crash reporting is not available on watchOS")
        }

        func uninstall(_: PostHogSDK) { /* no-op */ }
        func start() { /* no-op */ }
        func stop() { /* no-op */ }
    }
#endif
