import Foundation
@testable import PostHog
import Testing

/// https://github.com/PostHog/posthog-ios/issues/1066: the session manager must see the foreground before the
/// lifecycle integration captures `Application Opened`, or the event has no `$session_id`.
@Suite("Application Opened session", .serialized, .resetsGlobalState)
final class PostHogApplicationOpenedSessionTest {
    private let server: MockPostHogServer
    private let lifecycle: MockApplicationLifecyclePublisher

    init() {
        PostHogAppLifeCycleIntegration.clearInstalls()
        lifecycle = MockApplicationLifecyclePublisher()
        DI.main.appLifecyclePublisher = lifecycle
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
        DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
    }

    private func makeSDK(onApplicationOpened: @escaping (PostHogEvent) -> Void) -> PostHogSDK {
        let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9000")
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.preloadFeatureFlags = false
        config.setBeforeSend { event in
            if event.event == "Application Opened" {
                onApplicationOpened(event)
            }
            return event
        }
        return PostHogSDK.with(config)
    }

    @Test("Application Opened after a 31 minute background carries the new $session_id")
    func applicationOpenedAfterLongBackgroundHasSession() async {
        let runs = 40
        var runsWithoutSession = 0

        await withMockedClock { clock in
            for _ in 0 ..< runs {
                PostHogAppLifeCycleIntegration.clearInstalls()
                var lastSessionId: String?
                let sdk = makeSDK { event in
                    lastSessionId = event.properties["$session_id"] as? String
                }

                lifecycle.simulateAppDidBecomeActive()
                lifecycle.simulateAppDidEnterBackground()
                clock.date.addTimeInterval(31 * 60)
                lastSessionId = nil
                lifecycle.simulateAppDidBecomeActive()
                sdk.close()

                if lastSessionId.isNilOrEmpty {
                    runsWithoutSession += 1
                }
            }
        }

        #expect(runsWithoutSession == 0, "Application Opened had no $session_id in \(runsWithoutSession) of \(runs) runs")
    }
}
