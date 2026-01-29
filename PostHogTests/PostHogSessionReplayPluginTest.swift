#if os(iOS)
    @testable import PostHog
    import Testing

    @Suite("Session Replay Plugin Remote Config Tests")
    class PostHogSessionReplayPluginTests {
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

        @Test("Network plugin enabled when capturePerformance is object even with network_timing false")
        func networkPluginEnabledWhenObjectRegardlessOfNetworkTiming() {
            let config: [String: Any] = [
                "capturePerformance": [
                    "network_timing": false,
                    "web_vitals": true,
                ],
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin enabled when capturePerformance is empty object")
        func networkPluginEnabledWhenEmptyObject() {
            let config: [String: Any] = [
                "capturePerformance": [:],
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
    }
#endif
