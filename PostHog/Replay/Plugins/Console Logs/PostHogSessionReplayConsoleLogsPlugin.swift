//
//  PostHogSessionReplayConsoleLogsPlugin.swift
//  PostHog
//
//  Created by Ioannis Josephides on 09/05/2025.
//

#if os(iOS)
    import Foundation

    final class PostHogSessionReplayConsoleLogsPlugin: PostHogSessionReplayPlugin {
        private weak var postHog: PostHogSDK?
        private var isActive = false

        func start(postHog: PostHogSDK) {
            self.postHog = postHog
            isActive = true
            PostHogConsoleLogInterceptor.shared.startCapturing(config: postHog.config) { [weak self] output in
                self?.handleConsoleLog(output)
            }
            hedgeLog("[Session Replay] Console logs plugin started")
        }

        func stop() {
            postHog = nil
            isActive = false
            PostHogConsoleLogInterceptor.shared.stopCapturing()
            hedgeLog("[Session Replay] Console logs plugin stopped")
        }

        func resume() {
            guard !isActive, let postHog else { return }
            isActive = true
            PostHogConsoleLogInterceptor.shared.startCapturing(config: postHog.config) { [weak self] output in
                self?.handleConsoleLog(output)
            }
            hedgeLog("[Session Replay] Console logs plugin resumed")
        }

        func pause() {
            guard isActive else { return }
            isActive = false
            PostHogConsoleLogInterceptor.shared.stopCapturing()
            hedgeLog("[Session Replay] Console logs plugin paused")
        }

        private func handleConsoleLog(_ output: PostHogConsoleLogInterceptor.ConsoleOutput) {
            guard
                isActive,
                let postHog,
                postHog.isSessionReplayActive(),
                let sessionId = PostHogSessionManager.shared.getSessionId(at: output.timestamp)
            else {
                return
            }

            // `PostHogLogLevel`` needs to be an Int enum for objc interop
            // So we need to convert this to a String before sending upstream
            let level = switch output.level {
            case .error: "error"
            case .info: "info"
            case .warn: "warn"
            }

            var snapshotsData: [Any] = []
            let payloadData: [String: Any] = ["level": level, "payload": output.text]
            let pluginData: [String: Any] = ["plugin": "rrweb/console@1", "payload": payloadData]

            snapshotsData.append([
                "type": 6,
                "data": pluginData,
                "timestamp": output.timestamp.toMillis(),
            ])

            postHog.capture(
                "$snapshot",
                properties: [
                    "$snapshot_source": "mobile",
                    "$snapshot_data": snapshotsData,
                    "$session_id": sessionId,
                ],
                timestamp: output.timestamp
            )
        }
    }
#endif
