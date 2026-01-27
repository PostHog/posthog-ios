#if os(iOS)
    @testable import PostHog
    import Testing

    @Suite("Session Replay Plugin Remote Config Tests")
    class PostHogSessionReplayPluginTests {
        // MARK: - Console Logs Plugin Tests

        @Test("Console logs plugin enabled when remote config is nil")
        func consoleLogsPluginEnabledWhenConfigNil() {
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: nil) == true)
        }

        @Test("Console logs plugin enabled when sessionRecording missing")
        func consoleLogsPluginEnabledWhenSessionRecordingMissing() {
            let config: [String: Any] = ["someOtherKey": true]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin enabled when consoleLogRecordingEnabled is true")
        func consoleLogsPluginEnabledWhenTrue() {
            let config: [String: Any] = [
                "sessionRecording": ["consoleLogRecordingEnabled": true],
            ]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin enabled when consoleLogRecordingEnabled is missing")
        func consoleLogsPluginEnabledWhenKeyMissing() {
            let config: [String: Any] = [
                "sessionRecording": ["otherKey": "value"],
            ]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin disabled when consoleLogRecordingEnabled is false")
        func consoleLogsPluginDisabledWhenFalse() {
            let config: [String: Any] = [
                "sessionRecording": ["consoleLogRecordingEnabled": false],
            ]
            #expect(PostHogSessionReplayConsoleLogsPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        // MARK: - Network Plugin Tests

        @Test("Network plugin enabled when remote config is nil")
        func networkPluginEnabledWhenConfigNil() {
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: nil) == true)
        }

        @Test("Network plugin enabled when capturePerformance missing")
        func networkPluginEnabledWhenCapturePerformanceMissing() {
            let config: [String: Any] = ["someOtherKey": true]
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

        @Test("Network plugin disabled when capturePerformance is false")
        func networkPluginDisabledWhenCapturePerformanceIsFalse() {
            let config: [String: Any] = [
                "capturePerformance": false,
            ]
            #expect(PostHogSessionReplayNetworkPlugin.isEnabledRemotely(remoteConfig: config) == false)
        }
    }
#endif
