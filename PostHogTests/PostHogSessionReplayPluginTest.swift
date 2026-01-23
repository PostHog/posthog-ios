#if os(iOS)
    @testable import PostHog
    import Testing

    @Suite("Session Replay Plugin Remote Config Tests")
    class PostHogSessionReplayPluginTests {
        // MARK: - Console Logs Plugin Tests

        @Test("Console logs plugin enabled when remote config is nil")
        func consoleLogsPluginEnabledWhenConfigNil() {
            let plugin = PostHogSessionReplayConsoleLogsPlugin()
            #expect(plugin.isEnabledRemotely(remoteConfig: nil) == true)
        }

        @Test("Console logs plugin enabled when sessionRecording missing")
        func consoleLogsPluginEnabledWhenSessionRecordingMissing() {
            let plugin = PostHogSessionReplayConsoleLogsPlugin()
            let config: [String: Any] = ["someOtherKey": true]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin enabled when consoleLogRecordingEnabled is true")
        func consoleLogsPluginEnabledWhenTrue() {
            let plugin = PostHogSessionReplayConsoleLogsPlugin()
            let config: [String: Any] = [
                "sessionRecording": ["consoleLogRecordingEnabled": true],
            ]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin enabled when consoleLogRecordingEnabled is missing")
        func consoleLogsPluginEnabledWhenKeyMissing() {
            let plugin = PostHogSessionReplayConsoleLogsPlugin()
            let config: [String: Any] = [
                "sessionRecording": ["otherKey": "value"],
            ]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Console logs plugin disabled when consoleLogRecordingEnabled is false")
        func consoleLogsPluginDisabledWhenFalse() {
            let plugin = PostHogSessionReplayConsoleLogsPlugin()
            let config: [String: Any] = [
                "sessionRecording": ["consoleLogRecordingEnabled": false],
            ]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == false)
        }

        // MARK: - Network Plugin Tests

        @Test("Network plugin enabled when remote config is nil")
        func networkPluginEnabledWhenConfigNil() {
            let plugin = PostHogSessionReplayNetworkPlugin()
            #expect(plugin.isEnabledRemotely(remoteConfig: nil) == true)
        }

        @Test("Network plugin enabled when capturePerformance missing")
        func networkPluginEnabledWhenCapturePerformanceMissing() {
            let plugin = PostHogSessionReplayNetworkPlugin()
            let config: [String: Any] = ["someOtherKey": true]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin enabled when capturePerformance is an object")
        func networkPluginEnabledWhenCapturePerformanceIsObject() {
            let plugin = PostHogSessionReplayNetworkPlugin()
            let config: [String: Any] = [
                "capturePerformance": [
                    "network_timing": true,
                    "web_vitals": false
                ],
            ]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == true)
        }

        @Test("Network plugin disabled when capturePerformance is false")
        func networkPluginDisabledWhenCapturePerformanceIsFalse() {
            let plugin = PostHogSessionReplayNetworkPlugin()
            let config: [String: Any] = [
                "capturePerformance": false,
            ]
            #expect(plugin.isEnabledRemotely(remoteConfig: config) == false)
        }
    }
#endif
