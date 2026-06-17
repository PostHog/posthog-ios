//
//  PostHogErrorTrackingAutoCaptureIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/12/2025.
//

import Foundation

#if os(iOS) || os(macOS) || os(tvOS)
    // Vendored crash reporting is an implementation detail.
    @_implementationOnly import PHPLCrashReporter

    class PostHogErrorTrackingAutoCaptureIntegration: PostHogIntegration {
        private static let integrationInstallState = PostHogIntegrationInstallState()

        var requiresSwizzling: Bool { false }

        private weak var postHog: PostHogSDK?
        private var crashReporter: PHPLCrashReporter?
        /// Composes the crash context + exception steps into `customData`.
        private var crashCustomData: PostHogCrashCustomDataWriter?
        private var contextChangedToken: RegistrationToken?
        private var exceptionStepsChangedToken: RegistrationToken?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            if postHog.remoteConfig?.isAutocaptureExceptionsEnabled() == false {
                return .skipped(.disabledByRemoteConfig)
            }

            return installIfNeeded(using: Self.integrationInstallState) {
                if let crashReporter = setupCrashReporter() {
                    self.crashReporter = crashReporter
                    self.postHog = postHog
                    // Note: Order here matters, we need to process any pending crash report before enabling the crash reporter
                    processPendingCrashReportIfNeeded(reporter: crashReporter)
                    enableCrashReporter(reporter: crashReporter)

                    // Own the crash `customData`: compose context + steps and write them to the reporter.
                    // `crashReporter` is effectively immortal once enabled, so a strong capture is safe.
                    let crashCustomData = PostHogCrashCustomDataWriter(write: { crashReporter.customData = $0 })
                    self.crashCustomData = crashCustomData
                    contextChangedToken = postHog.onEventContextChanged.subscribe { [weak crashCustomData] context in
                        crashCustomData?.setContext(context)
                    }
                    exceptionStepsChangedToken = postHog.onExceptionStepsChanged.subscribe { [weak crashCustomData] steps in
                        crashCustomData?.setSteps(steps)
                    }
                }
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            uninstallIfNeeded(from: postHog, installedPostHog: self.postHog, state: Self.integrationInstallState) {
                stop()
                contextChangedToken = nil
                exceptionStepsChangedToken = nil
                crashCustomData = nil
                crashReporter = nil
                self.postHog = nil
            }
        }

        func start() {
            // No-op for crash reporting. Always active once installed
        }

        func stop() {
            // No-op for crash reporting. Always active once installed
        }

        // MARK: - Private Methods

        private func setupCrashReporter() -> PHPLCrashReporter? {
            // Configure PHPLCrashReporter
            // Note: Mach exception handling is not available on tvOS, so we fall back to BSD signal handlers
            #if os(tvOS)
                let signalHandlerType: PHPLCrashReporterSignalHandlerType = .BSD
            #else
                let signalHandlerType: PHPLCrashReporterSignalHandlerType = .mach
            #endif

            let config = PHPLCrashReporterConfig(
                signalHandlerType: signalHandlerType,
                symbolicationStrategy: [], // No local symbolication, we'll be doing server-side
                shouldRegisterUncaughtExceptionHandler: true
            )

            guard let reporter = PHPLCrashReporter(configuration: config) else {
                hedgeLog("Failed to create PHPLCrashReporter instance")
                return nil
            }

            return reporter
        }

        private func processPendingCrashReportIfNeeded(reporter: PHPLCrashReporter) {
            // Check for pending crash report FIRST (before enabling for new crashes)
            if reporter.hasPendingCrashReport() {
                hedgeLog("Found pending crash report, processing...")
                processPendingCrashReport()
            }
        }

        private func enableCrashReporter(reporter: PHPLCrashReporter) {
            // Check for debugger first. Crash handler won't work when debugging
            if PostHogDebugUtils.isDebuggerAttached() {
                hedgeLog("Crash handler is disabled because a debugger is attached. Crashes will be caught by the debugger instead.")
                return
            }

            // Enable crash reporter for this session
            do {
                try reporter.enableAndReturnError()
                hedgeLog("PHPLCrashReporter enabled successfully")
            } catch {
                hedgeLog("Failed to enable PHPLCrashReporter: \(error)")
            }
        }

        private func processPendingCrashReport() {
            guard let crashReporter, let postHog else {
                return
            }

            // Load and purge BEFORE processing to prevent crash loops.
            // If processing itself crashes (e.g., corrupt report), the report is already
            // gone so the app won't crash again on next launch.
            let crashData: Data
            do {
                crashData = try crashReporter.loadPendingCrashReportDataAndReturnError()
            } catch {
                hedgeLog("Failed to load crash report: \(error)")
                crashReporter.purgePendingCrashReport()
                return
            }

            crashReporter.purgePendingCrashReport()

            do {
                let crashReport = try PHPLCrashReport(data: crashData)

                // customData is the saved context with the exception steps recorded before the crash
                // nested under `$exception_steps`.
                var savedContext: [String: Any] = [:]
                var crashSteps: [[String: Any]] = []
                if let customData = crashReport.customData, let decoded = fromJSONData(customData) {
                    savedContext = decoded
                    crashSteps = decoded[PostHogExceptionStepFields.stepsKey] as? [[String: Any]] ?? []
                }

                // Extract identity and event properties from saved context
                let crashDistinctId = savedContext["distinct_id"] as? String
                let crashEventProperties = savedContext["event_properties"] as? [String: Any] ?? [:]

                // Collect crash-specific event properties (stack traces, exceptions etc)
                let exceptionProperties = PostHogCrashReportProcessor.processReport(crashReport, config: postHog.config.errorTrackingConfig)

                // Merge: crash-time event properties as base, exception properties on top
                var finalProperties = crashEventProperties.merging(exceptionProperties) { _, new in new }

                // Attach steps recorded before the crash, unless the crash context already had them.
                if finalProperties[PostHogExceptionStepFields.stepsKey] == nil, !crashSteps.isEmpty {
                    finalProperties[PostHogExceptionStepFields.stepsKey] = crashSteps
                }

                // Honor `errorTrackingConfig.ignoredExceptionTypes`. The
                // primary use case is React Native's `RCTFatalException`,
                // which is rethrown for every fatal JS error and would
                // otherwise duplicate the JS-side `$exception` event with
                // a redundant native stack trace (see #653).
                let ignored = postHog.config.errorTrackingConfig.ignoredExceptionTypes
                if !ignored.isEmpty, PostHogErrorTrackingAutoCaptureIntegration.exceptionListMatchesIgnoredTypes(finalProperties, ignoredTypes: ignored) {
                    hedgeLog("Crash report skipped: exception type is in errorTrackingConfig.ignoredExceptionTypes")
                    return
                }

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
                hedgeLog("Failed to process crash report: \(error)")
            }
        }

        /// Returns `true` if any entry in `properties["$exception_list"]` has a
        /// `type` matching one of `ignoredTypes`. Walks the exception list rather
        /// than only the outermost entry so a wrapped exception whose underlying
        /// cause is, e.g., `RCTFatalException` is still suppressed. Match is
        /// case-sensitive and exact (the field is a class name, not free text).
        static func exceptionListMatchesIgnoredTypes(_ properties: [String: Any], ignoredTypes: [String]) -> Bool {
            guard let exceptionList = properties["$exception_list"] as? [[String: Any]] else {
                return false
            }
            let ignored = Set(ignoredTypes)
            return exceptionList.contains { entry in
                if let type = entry["type"] as? String, ignored.contains(type) {
                    return true
                }
                return false
            }
        }
    }

#else
    // watchOS stub - crash reporting is not available
    class PostHogErrorTrackingAutoCaptureIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { false }

        func install(_: PostHogSDK) -> PostHogIntegrationInstallResult {
            .skipped(.notAvailableOnPlatform)
        }

        func uninstall(_: PostHogSDK) { /* no-op */ }
        func start() { /* no-op */ }
        func stop() { /* no-op */ }
    }
#endif
