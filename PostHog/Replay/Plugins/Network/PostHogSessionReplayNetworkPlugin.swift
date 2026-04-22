//
//  PostHogSessionReplayNetworkPlugin.swift
//  PostHog
//
//  Created by Ioannis Josephides on 28/05/2025.
//

#if os(iOS)
    import Foundation

    /// Session replay plugin that captures network requests using URLSession swizzling.
    final class PostHogSessionReplayNetworkPlugin: PostHogSessionReplayPlugin {
        private var interceptor: URLSessionInterceptor?
        private var registrationId: UUID?
        private weak var postHog: PostHogSDK?
        private var isActive = false

        required init() { /**/ }

        func start(postHog: PostHogSDK) {
            self.postHog = postHog

            let interceptor = URLSessionInterceptor(
                shouldCapture: shouldCaptureNetworkSample,
                shouldCaptureRequest: { [weak self] request in
                    self?.shouldCaptureNetworkRequest(request) ?? false
                },
                onCapture: handleNetworkSample,
                getSessionId: { [weak self] date in
                    self?.postHog?.sessionManager.getSessionId(at: date)
                }
            )

            do {
                registrationId = try URLSessionInstrumentation.shared.register(
                    taskCreated: { [weak interceptor] task, session in
                        interceptor?.taskCreated(task: task, session: session)
                    },
                    taskCompleted: { [weak interceptor] task, error in
                        interceptor?.taskCompleted(task: task, error: error)
                    }
                )
                self.interceptor = interceptor
                hedgeLog("[Session Replay] Network telemetry plugin started")
                isActive = true
            } catch {
                hedgeLog("[Session Replay] Failed to initialize network telemetry: \(error)")
            }
        }

        func stop() {
            if let registrationId {
                URLSessionInstrumentation.shared.unregister(registrationId)
            }
            registrationId = nil
            interceptor?.stop()
            interceptor = nil
            postHog = nil
            isActive = false
            hedgeLog("[Session Replay] Network telemetry plugin stopped")
        }

        func resume() {
            guard !isActive else { return }
            isActive = true
            hedgeLog("[Session Replay] Network telemetry plugin resumed")
        }

        func pause() {
            guard isActive else { return }
            isActive = false
            hedgeLog("[Session Replay] Network telemetry plugin paused")
        }

        // see: https://github.com/PostHog/posthog-js/blob/c81ee34096a780b13e97a862197d4a6fdedb749a/packages/browser/src/extensions/replay/external/lazy-loaded-session-recorder.ts#L470-L492
        static func isEnabledRemotely(remoteConfig: [String: Any]?) -> Bool {
            guard let capturePerformanceValue = remoteConfig?["capturePerformance"] else {
                // No remote config means disabled
                return false
            }

            // When capturePerformance is a boolean, use it directly
            if let isEnabled = capturePerformanceValue as? Bool {
                return isEnabled
            }
            // When enabled, capturePerformance is an object, check network_timing key
            if let perfConfig = capturePerformanceValue as? [String: Any],
               let networkTiming = perfConfig["network_timing"] as? Bool
            {
                return networkTiming
            }
            // fallback to disabled
            return false
        }

        /// Mirrors the browser SDK's replay network capture filtering by ignoring
        /// PostHog's own ingestion requests relative to the configured API host.
        static func shouldIgnoreNetworkRequest(url: URL?, apiHost: URL, snapshotEndpoint: String) -> Bool {
            guard let url, matchesAPIHost(url, apiHost: apiHost) else {
                return false
            }

            let path = strippingAPIHostPathPrefix(from: url.path, apiHostPath: apiHost.path)
            let ignoredPaths = [snapshotEndpoint, "/batch", "/e/", "/i/"]

            return ignoredPaths.contains { ignoredPath in
                pathMatches(path, ignoredPath: ignoredPath)
            }
        }

        private static func matchesAPIHost(_ url: URL, apiHost: URL) -> Bool {
            url.scheme?.lowercased() == apiHost.scheme?.lowercased()
                && url.host?.lowercased() == apiHost.host?.lowercased()
                && effectivePort(for: url) == effectivePort(for: apiHost)
        }

        private static func effectivePort(for url: URL) -> Int? {
            if let port = url.port {
                return port
            }

            switch url.scheme?.lowercased() {
            case "http":
                return 80
            case "https":
                return 443
            default:
                return nil
            }
        }

        private static func strippingAPIHostPathPrefix(from path: String, apiHostPath: String) -> String {
            let normalizedAPIHostPath = normalizedAPIHostPathPrefix(apiHostPath)

            guard !normalizedAPIHostPath.isEmpty,
                  path == normalizedAPIHostPath || path.hasPrefix("\(normalizedAPIHostPath)/")
            else {
                return path
            }

            let strippedPath = String(path.dropFirst(normalizedAPIHostPath.count))
            if strippedPath.isEmpty {
                return "/"
            }

            return strippedPath.hasPrefix("/") ? strippedPath : "/\(strippedPath)"
        }

        private static func normalizedAPIHostPathPrefix(_ path: String) -> String {
            guard !path.isEmpty, path != "/" else {
                return ""
            }

            return path.hasSuffix("/") ? String(path.dropLast()) : path
        }

        private static func pathMatches(_ path: String, ignoredPath: String) -> Bool {
            let normalizedIgnoredPath = normalizedIgnoredPathPrefix(ignoredPath)
            guard !normalizedIgnoredPath.isEmpty else {
                return false
            }

            if normalizedIgnoredPath.hasSuffix("/") {
                let exactPath = String(normalizedIgnoredPath.dropLast())
                return path == exactPath || path.hasPrefix(normalizedIgnoredPath)
            }

            return path == normalizedIgnoredPath || path.hasPrefix("\(normalizedIgnoredPath)/")
        }

        private static func normalizedIgnoredPathPrefix(_ path: String) -> String {
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                return ""
            }

            return trimmedPath.hasPrefix("/") ? trimmedPath : "/\(trimmedPath)"
        }

        private func shouldCaptureNetworkSample() -> Bool {
            guard let postHog else { return false }
            return isActive && postHog.config.sessionReplayConfig.captureNetworkTelemetry && postHog.isSessionReplayActive()
        }

        private func shouldCaptureNetworkRequest(_ request: URLRequest) -> Bool {
            guard let postHog else { return false }

            return !Self.shouldIgnoreNetworkRequest(
                url: request.url,
                apiHost: postHog.config.host,
                snapshotEndpoint: postHog.config.snapshotEndpoint
            )
        }

        private func handleNetworkSample(sample: NetworkSample) {
            guard let postHog else { return }

            let timestamp = sample.timeOrigin

            var snapshotsData: [Any] = []

            let requestsData = [sample.toDict()]
            let payloadData: [String: Any] = ["requests": requestsData]
            let pluginData: [String: Any] = ["plugin": "rrweb/network@1", "payload": payloadData]

            let data: [String: Any] = [
                "type": 6,
                "data": pluginData,
                "timestamp": timestamp.toMillis(),
            ]
            snapshotsData.append(data)

            postHog.capture(
                "$snapshot",
                properties: [
                    "$snapshot_source": "mobile",
                    "$snapshot_data": snapshotsData,
                    "$session_id": sample.sessionId,
                ],
                timestamp: sample.timeOrigin
            )
        }
    }
#endif
