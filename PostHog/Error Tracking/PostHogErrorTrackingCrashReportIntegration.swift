//
//  PostHogErrorTrackingCrashReportIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/12/2025.
//

import Foundation

#if os(iOS) || os(macOS) || os(tvOS)
    import CrashReporter

    class PostHogErrorTrackingCrashReportIntegration: PostHogIntegration {
        private static let integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        var requiresSwizzling: Bool { false }

        private weak var postHog: PostHogSDK?
        private var crashReporter: PLCrashReporter?

        func install(_ postHog: PostHogSDK) throws {
            try PostHogErrorTrackingCrashReportIntegration.integrationInstalledLock.withLock {
                if PostHogErrorTrackingCrashReportIntegration.integrationInstalled {
                    throw InternalPostHogError(description: "Crash report integration already installed to another PostHogSDK instance.")
                }
                PostHogErrorTrackingCrashReportIntegration.integrationInstalled = true
            }

            self.postHog = postHog
            if let crashReporter = setupCrashReporter() {
                // Note: Order here matters, we need to process any pending crash report before enabling the crash reporter
                processPendingCrashReportIfNeeded(reporter: crashReporter)
                enableCrashReporter(reporter: crashReporter)
                self.crashReporter = crashReporter
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            if self.postHog === postHog || self.postHog == nil {
                stop()
                crashReporter = nil
                self.postHog = nil
                PostHogErrorTrackingCrashReportIntegration.integrationInstalledLock.withLock {
                    PostHogErrorTrackingCrashReportIntegration.integrationInstalled = false
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

                // Extract context from crash report's customData
                var crashContext: [String: Any] = [:]
                if let customData = crashReport.customData {
                    crashContext = (try? JSONSerialization.jsonObject(with: customData, options: [])) as? [String: Any] ?? [:]
                }

                // Process crash report and create $exception event
                let exceptionProperties = PostHogCrashReportProcessor.processReport(
                    crashReport,
                    crashContext: crashContext
                )

                // Capture the crash event
                postHog.capture(
                    "$exception",
                    properties: exceptionProperties,
                    userProperties: nil,
                    userPropertiesSetOnce: nil,
                    groups: nil
                )

                hedgeLog("Crash report processed and captured")

            } catch {
                // Best effort for now. We log and ignore and let the crash report be purged.
                // - On a new crash, old report will be overwritten anyway
                // - Keeping the report around could risk infinite retry loop until next crash if it's corrupt
                // - This could fail because of a transient error though, in the future we could check the returned error
                //   and only purge if PLCrashReporterErrorCrashReportInvalid
                hedgeLog("Failed to process crash report: \(error)")
            }

            // Always purge the crash report after processing
            crashReporter.purgePendingCrashReport()
        }
    }

#else
    // watchOS stub - crash reporting is not available
    class PostHogErrorTrackingCrashReportIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { false }

        func install(_: PostHogSDK) throws {
            hedgeLog("Crash reporting is not available on watchOS")
        }

        func uninstall(_: PostHogSDK) { /* no-op */ }
        func start() { /* no-op */ }
        func stop() { /* no-op */ }
    }
#endif
