#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Session Replay Plugin Remote Config Tests")
    class PostHogSessionReplayPluginTests {
        struct IgnoredNetworkRequestCase: CustomTestStringConvertible {
            let name: String
            let requestURL: String
            let apiHost: String
            let snapshotEndpoint: String
            let expected: Bool

            var testDescription: String { name }
        }

        // MARK: - Console Logs Plugin Tests

        @Test("Console logs plugin disabled when remote config is nil")
        func consoleLogsPluginDisabledWhenConfigNil() {
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: nil) == false)
        }

        @Test("Console logs plugin disabled when sessionRecording missing")
        func consoleLogsPluginDisabledWhenSessionRecordingMissing() {
            let config: [String: Any] = ["someOtherKey": true]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Console logs plugin enabled when consoleLogRecordingEnabled is true")
        func consoleLogsPluginEnabledWhenTrue() {
            let config: [String: Any] = [
                "sessionRecording": ["consoleLogRecordingEnabled": true],
            ]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin disabled when consoleLogRecordingEnabled is missing")
        func consoleLogsPluginDisabledWhenKeyMissing() {
            let config: [String: Any] = [
                "sessionRecording": ["otherKey": "value"],
            ]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Console logs plugin disabled when consoleLogRecordingEnabled is false")
        func consoleLogsPluginDisabledWhenFalse() {
            let config: [String: Any] = [
                "sessionRecording": ["consoleLogRecordingEnabled": false],
            ]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        // MARK: - Network Plugin Tests

        @Test("Network plugin disabled when remote config is nil")
        func networkPluginDisabledWhenConfigNil() {
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: nil) == false)
        }

        @Test("Network plugin disabled when capturePerformance missing")
        func networkPluginDisabledWhenCapturePerformanceMissing() {
            let config: [String: Any] = ["someOtherKey": true]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Network plugin enabled when capturePerformance is true")
        func networkPluginEnabledWhenCapturePerformanceIsTrue() {
            let config: [String: Any] = ["capturePerformance": true]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin enabled when capturePerformance is an object")
        func networkPluginEnabledWhenCapturePerformanceIsObject() {
            let config: [String: Any] = [
                "capturePerformance": [
                    "network_timing": true,
                    "web_vitals": false,
                ],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin disabled when capturePerformance object has network_timing false")
        func networkPluginDisabledWhenNetworkTimingFalse() {
            let config: [String: Any] = [
                "capturePerformance": [
                    "network_timing": false,
                    "web_vitals": true,
                ],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Network plugin disabled when capturePerformance is empty object")
        func networkPluginDisabledWhenEmptyObject() {
            let config: [String: Any] = [
                "capturePerformance": [:],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Network plugin disabled when capturePerformance object missing network_timing")
        func networkPluginDisabledWhenNetworkTimingMissing() {
            let config: [String: Any] = [
                "capturePerformance": [
                    "web_vitals": true,
                ],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Network plugin disabled when capturePerformance object has null web_vitals_allowed_metrics")
        func networkPluginDisabledWhenNetworkTimingIsNull() {
            let config: [String: Any?] = [
                "capturePerformance": [
                    "network_timing": true,
                    "web_vitals_allowed_metrics": nil,
                ],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin disabled when capturePerformance object has NSNull web_vitals_allowed_metrics")
        func networkPluginDisabledWhenNetworkTimingIsNSNull() {
            let config: [String: Any?] = [
                "capturePerformance": [
                    "network_timing": true,
                    "web_vitals_allowed_metrics": NSNull(),
                ],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin disabled when capturePerformance is false")
        func networkPluginDisabledWhenCapturePerformanceIsFalse() {
            let config: [String: Any] = [
                "capturePerformance": false,
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        @Test("Network replay capture ignores PostHog ingestion requests", arguments: [
            IgnoredNetworkRequestCase(
                name: "ignores snapshot ingestion on the configured host",
                requestURL: "https://us.i.posthog.com/s/?ip=1",
                apiHost: "https://us.i.posthog.com",
                snapshotEndpoint: "/s/",
                expected: true
            ),
            IgnoredNetworkRequestCase(
                name: "ignores batch ingestion on the configured host",
                requestURL: "https://us.i.posthog.com/batch",
                apiHost: "https://us.i.posthog.com",
                snapshotEndpoint: "/s/",
                expected: true
            ),
            IgnoredNetworkRequestCase(
                name: "ignores replay ingestion behind a reverse proxy path",
                requestURL: "https://app.posthog.com/ingest/s/?ip=1",
                apiHost: "https://app.posthog.com/ingest",
                snapshotEndpoint: "/s/",
                expected: true
            ),
            IgnoredNetworkRequestCase(
                name: "ignores batch ingestion behind a reverse proxy path",
                requestURL: "https://app.posthog.com/ingest/batch",
                apiHost: "https://app.posthog.com/ingest",
                snapshotEndpoint: "/s/",
                expected: true
            ),
            IgnoredNetworkRequestCase(
                name: "ignores a remotely configured snapshot endpoint",
                requestURL: "https://us.i.posthog.com/newS/?ip=1",
                apiHost: "https://us.i.posthog.com",
                snapshotEndpoint: "/newS/",
                expected: true
            ),
            IgnoredNetworkRequestCase(
                name: "ignores legacy ingestion paths on the configured host",
                requestURL: "https://us.i.posthog.com/i/v0/e/?ip=1",
                apiHost: "https://us.i.posthog.com",
                snapshotEndpoint: "/s/",
                expected: true
            ),
            IgnoredNetworkRequestCase(
                name: "does not ignore non ingestion paths on the configured host",
                requestURL: "https://us.i.posthog.com/flags?v=2",
                apiHost: "https://us.i.posthog.com",
                snapshotEndpoint: "/s/",
                expected: false
            ),
            IgnoredNetworkRequestCase(
                name: "does not ignore requests outside the reverse proxy base path",
                requestURL: "https://app.posthog.com/ingest-extra/batch",
                apiHost: "https://app.posthog.com/ingest",
                snapshotEndpoint: "/s/",
                expected: false
            ),
            IgnoredNetworkRequestCase(
                name: "does not ignore third party hosts with similar paths",
                requestURL: "https://api.example.com/batch",
                apiHost: "https://us.i.posthog.com",
                snapshotEndpoint: "/s/",
                expected: false
            ),
        ])
        func networkReplayCaptureIgnoresPostHogIngestionRequests(_ testCase: IgnoredNetworkRequestCase) throws {
            let requestURL = try #require(URL(string: testCase.requestURL))
            let apiHost = try #require(URL(string: testCase.apiHost))

            #expect(
                PostHogSessionReplayNetworkPlugin.shouldIgnoreNetworkRequest(
                    url: requestURL,
                    apiHost: apiHost,
                    snapshotEndpoint: testCase.snapshotEndpoint
                ) == testCase.expected
            )
        }
    }
#endif
