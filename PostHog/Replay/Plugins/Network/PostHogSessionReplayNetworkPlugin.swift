//
//  PostHogSessionReplayNetworkPlugin.swift
//  PostHog
//
//  Created by Ioannis Josephides on 28/05/2025.
//

#if os(iOS)
    import Foundation

    /// Session replay plugin that captures network requests using URLSession swizzling.
    class PostHogSessionReplayNetworkPlugin: PostHogSessionReplayPlugin {
        private var sessionSwizzler: URLSessionSwizzler?
        private var postHog: PostHogSDK?
        private var isActive = false

        func start(postHog: PostHogSDK) {
            self.postHog = postHog
            do {
                sessionSwizzler = try URLSessionSwizzler(
                    shouldCapture: shouldCaptureNetworkSample,
                    onCapture: handleNetworkSample
                )
                sessionSwizzler?.swizzle()
                hedgeLog("[Session Replay] Network telemetry plugin started")
                isActive = true
            } catch {
                hedgeLog("[Session Replay] Failed to initialize network telemetry: \(error)")
            }
        }

        func stop() {
            sessionSwizzler?.unswizzle()
            sessionSwizzler = nil
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

        private func shouldCaptureNetworkSample() -> Bool {
            guard let postHog else { return false }
            return isActive && postHog.config.sessionReplayConfig.captureNetworkTelemetry && postHog.isSessionReplayActive()
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
