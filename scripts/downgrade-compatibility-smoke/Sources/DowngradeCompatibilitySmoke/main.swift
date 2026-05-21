import Foundation
import PostHog

let mode = CommandLine.arguments.dropFirst().first ?? "read"
let token = ProcessInfo.processInfo.environment["POSTHOG_DOWNGRADE_TEST_TOKEN"] ?? "downgrade_compatibility_project"

let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
print("Application Support: \(appSupport.path)")

#if CURRENT_STORAGE_WRITER
    let config = PostHogConfig(projectToken: token, host: "http://127.0.0.1:9")
#else
    let config = PostHogConfig(apiKey: token, host: "http://127.0.0.1:9")
#endif
config.flushAt = 10_000
config.maxQueueSize = 10_000
config.preloadFeatureFlags = false
config.captureApplicationLifecycleEvents = false
config.captureScreenViews = false
config.enableSwizzling = false

#if CURRENT_STORAGE_WRITER
    config.logs.flushAt = 10_000
    config.logs.maxBufferSize = 10_000
#endif

PostHogSDK.shared.setup(config)

switch mode {
case "write":
    PostHogSDK.shared.identify(
        "downgrade-compatibility-user",
        userProperties: ["source": "downgrade-compatibility"]
    )
    PostHogSDK.shared.group(
        type: "organization",
        key: "posthog",
        groupProperties: ["ci": true]
    )

    for index in 0 ..< 5 {
        PostHogSDK.shared.capture(
            "downgrade compatibility event",
            properties: ["index": index, "source": "current-sdk"]
        )
    }

    #if CURRENT_STORAGE_WRITER
        for index in 0 ..< 2 {
            PostHogSDK.shared.capture(
                "$snapshot",
                properties: [
                    "$session_id": "downgrade-compatibility-session",
                    "$snapshot_data": [
                        "type": 4,
                        "data": ["href": "http://example.com/\(index)"],
                    ],
                ]
            )
        }

        PostHogSDK.shared.captureLog(
            "downgrade compatibility log",
            level: .warn,
            attributes: ["source": "current-sdk", "index": 0]
        )
        PostHogSDK.shared.captureLog(
            "downgrade compatibility log",
            level: .error,
            attributes: ["source": "current-sdk", "index": 1]
        )
    #endif

    print("Wrote SDK state for token \(token)")
case "read":
    PostHogSDK.shared.capture(
        "downgrade compatibility read smoke",
        properties: ["source": "downgraded-sdk"]
    )
    print("Downgraded SDK started and read latest state for token \(token)")
default:
    fatalError("Unknown mode: \(mode)")
}
