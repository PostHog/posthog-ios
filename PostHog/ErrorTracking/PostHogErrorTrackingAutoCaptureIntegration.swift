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

        static func clearInstalls() {
            integrationInstallState.clear()
            pendingEnableToken = nil
        }

        var requiresSwizzling: Bool { false }

        private weak var postHog: PostHogSDK?
        private var crashReporter: PHPLCrashReporter?
        /// Composes the crash context + exception steps into `customData`.
        private var crashCustomData: PostHogCrashCustomDataWriter?
        private var contextChangedToken: RegistrationToken?
        private var exceptionStepsChangedToken: RegistrationToken?
        private var remoteConfigLoadedToken: RegistrationToken?
        /// Held while a cached-disabled start waits for a live `/config` that may re-enable autocapture.
        /// Static (like `integrationInstallState`) and retains `self` so the skipped instance survives
        /// until the live config lands; cleared once it does.
        private static var pendingEnableToken: RegistrationToken?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            // Only block install when real config data (a successful live fetch or disk cache)
            // disables autocapture. With no data — first launch, no cache, or a *failed* /config —
            // default to installing so a first-launch crash isn't missed. A failed fetch sets
            // `hasFetchedRemoteConfig` but stores none, so pair it with a data-present check;
            // `hasFetchedRemoteConfig` also flips last (after the config is stored and applied), so
            // the pairing never reads a half-applied live config.
            let hasRemoteConfig = postHog.remoteConfig?.hasCachedRemoteConfig == true
                || (postHog.remoteConfig?.hasFetchedRemoteConfig == true
                    && postHog.remoteConfig?.getRemoteConfig() != nil)
            if hasRemoteConfig,
               postHog.remoteConfig?.isAutocaptureExceptionsEnabled() == false
            {
                // The native handler can't be torn down once enabled, so a crash during a prior
                // default-on first-launch window may have left a report on disk. Config now says
                // autocapture is disabled, so purge it rather than let a later re-enable transmit
                // a crash that happened while the project was opted out.
                purgePendingCrashReportIfNeeded()

                // The disable verdict may have come purely from a disk-cached config. If the live
                // /config has not landed yet, watch for it: a fresh response that re-enables
                // autocapture should install now rather than wait for the next launch.
                if postHog.remoteConfig?.hasFetchedRemoteConfig == false {
                    watchForRemoteEnable(postHog)
                }
                return .skipped(.disabledByRemoteConfig)
            }

            // Live config enabled autocapture: cancel any pending cached-disabled watch.
            Self.pendingEnableToken = nil

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

                    // If remote config was not yet loaded at install time, subscribe so we can
                    // remove the integration if the freshly-loaded config disables autocapture.
                    if postHog.remoteConfig?.hasFetchedRemoteConfig == false {
                        remoteConfigLoadedToken = postHog.remoteConfig?.onRemoteConfigLoaded.subscribe { [weak self, weak postHog] _ in
                            guard let self, let postHog else { return }
                            self.remoteConfigLoadedToken = nil
                            if postHog.remoteConfig?.isAutocaptureExceptionsEnabled() == false {
                                postHog.removeIntegration(self)
                            }
                        }
                    }
                }
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            uninstallIfNeeded(from: postHog, installedPostHog: self.postHog, state: Self.integrationInstallState) {
                stop()
                remoteConfigLoadedToken = nil
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

        /// Discards any on-disk crash report without processing it. Creating the reporter here
        /// only reads/purges the report file; it does not enable the native handler.
        private func purgePendingCrashReportIfNeeded() {
            guard let reporter = setupCrashReporter(), reporter.hasPendingCrashReport() else {
                return
            }
            hedgeLog("Autocapture disabled by remote config, purging pending crash report")
            reporter.purgePendingCrashReport()
        }

        /// Subscribes to the live `/config` for the case where a disk-cached config disabled
        /// autocapture. If the fresh response re-enables it, install the integration. The closure
        /// retains `self` (via the static token) so the skipped instance stays alive until then.
        private func watchForRemoteEnable(_ postHog: PostHogSDK) {
            Self.pendingEnableToken = postHog.remoteConfig?.onRemoteConfigLoaded.subscribe { [self] _ in
                Self.pendingEnableToken = nil
                if postHog.remoteConfig?.isAutocaptureExceptionsEnabled() == true {
                    postHog.addIntegration(self)
                }
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
                guard let exType = entry["type"] as? String else { return false }
                return ignored.contains(exType)
            }
        }
    }

#else
    // watchOS/visionOS stub - crash reporting is not available on these platforms
    class PostHogErrorTrackingAutoCaptureIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { false }

        func install(_: PostHogSDK) -> PostHogIntegrationInstallResult {
            .skipped(.notAvailableOnPlatform)
        }

        func uninstall(_: PostHogSDK) { /* no-op */ }
        func start() { /* no-op */ }
        func stop() { /* no-op */ }

        /// Crash reporting is unavailable on this platform; always returns `false`.
        static func exceptionListMatchesIgnoredTypes(_: [String: Any], ignoredTypes _: [String]) -> Bool {
            false
        }
    }
#endif
