//
//  PostHogMemoryExceptionReporter.swift
//  PostHog
//

import Foundation

// `MemoryExceptionDiagnostic` ships in the iOS 27 SDK (Swift 6.4), is Swift-only, and is unavailable on Mac Catalyst.
#if os(iOS) && !targetEnvironment(macCatalyst) && compiler(>=6.4)
    import MetricKit

    /// Reports out-of-memory terminations as `$exception` events.
    ///
    /// When the system kills the app for exceeding its memory limit it sends SIGKILL, which no
    /// in-process crash handler can catch. From iOS 27, MetricKit delivers a
    /// `MemoryExceptionDiagnostic` for it on a later launch.
    final class PostHogMemoryExceptionReporter {
        private weak var postHog: PostHogSDK?
        private let contextStore: PostHogProcessContextStore
        private var task: Task<Void, Never>?

        init(postHog: PostHogSDK, contextStore: PostHogProcessContextStore) {
            self.postHog = postHog
            self.contextStore = contextStore
        }

        func start() {
            guard #available(iOS 27.0, *) else { return }
            // MetricKit delivers nothing once the manager is deallocated, so the task must own it.
            let manager = MetricManager()
            task = Task.detached(priority: .utility) { [weak self] in
                for await report in manager.diagnosticReports {
                    guard !Task.isCancelled else { return }
                    guard case let .memoryException(diagnostic) = report.result else { continue }
                    self?.capture(diagnostic, report: report)
                }
            }
        }

        func stop() {
            task?.cancel()
            task = nil
        }

        @available(iOS 27.0, *)
        func capture(_ diagnostic: MemoryExceptionDiagnostic, report: DiagnosticReport) {
            guard let postHog else { return }

            var properties = PostHogMemoryExceptionProcessor.processFrames(
                Self.frames(from: diagnostic.callStackTree),
                config: postHog.config.errorTrackingConfig
            )

            var distinctId: String?
            if let pid = report.environment.pid,
               let saved = contextStore.takeContext(pid: pid, notAfter: report.timeRange.end)
            {
                distinctId = saved["distinct_id"] as? String
                let eventProperties = saved["event_properties"] as? [String: Any] ?? [:]
                properties = eventProperties.merging(properties) { _, new in new }
                if let steps = saved[PostHogExceptionStepFields.stepsKey] as? [[String: Any]], !steps.isEmpty {
                    properties[PostHogExceptionStepFields.stepsKey] = steps
                }
            } else {
                // No saved context: describe the device and SDK, but not the current session.
                if let context = postHog.context {
                    properties.merge(context.staticContext()) { current, _ in current }
                    properties.merge(context.sdkInfo()) { current, _ in current }
                }
                properties["$app_version"] = report.environment.applicationVersion
                properties["$app_build"] = report.environment.applicationBuildVersion
            }

            postHog.captureInternal(
                "$exception",
                distinctId: distinctId,
                properties: properties,
                timestamp: report.timeRange.end,
                skipBuildProperties: true
            )
            hedgeLog("Memory exception report processed")
        }

        /// The attributed thread's frames, innermost first.
        @available(iOS 27.0, *)
        static func frames(from tree: CallStackTree) -> [PostHogDiagnosticFrame] {
            guard let thread = tree.callStackThreads.first(where: { $0.threadAttributed == true })
                ?? tree.callStackThreads.first
            else {
                return []
            }

            // Each frame's caller is its single sub-frame.
            var frames: [PostHogDiagnosticFrame] = []
            var next = thread.rootFrames.first
            while let frame = next {
                if let address = frame.address {
                    frames.append(PostHogDiagnosticFrame(
                        binaryUUID: frame.binaryUUID,
                        binaryName: frame.binaryName(from: tree),
                        address: address,
                        offsetIntoBinaryTextSegment: frame.offsetIntoBinaryTextSegment
                    ))
                }
                next = frame.subFrames.first
            }
            return frames
        }
    }
#endif
