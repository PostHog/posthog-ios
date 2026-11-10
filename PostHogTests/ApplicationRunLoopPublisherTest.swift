#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Application Run Loop Publisher", .serialized)
    final class ApplicationRunLoopPublisherTest {
        private let mockLifecycle = MockApplicationLifecyclePublisher()

        init() {
            DI.main.appLifecyclePublisher = mockLifecycle
        }

        deinit {
            DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
        }

        /// Lets the real main run loop go idle and wake again, which is what produces
        /// `.beforeWaiting` / `.afterWaiting`, then drains the main-queue deliveries the observer
        /// enqueued. A nested `CFRunLoopRunInMode` is no good here: with no input source of its own it
        /// returns `kCFRunLoopRunFinished` without ever cycling.
        @MainActor
        private func settle(cycles: Int = 3, milliseconds: UInt64 = 20) async {
            for _ in 0 ..< cycles {
                try? await Task.sleep(nanoseconds: milliseconds * NSEC_PER_MSEC)
            }
            await drainMain()
        }

        private func runOffMain(_ body: @escaping () -> Void) throws {
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                body()
                finished.signal()
            }
            try #require(finished.wait(timeout: .now() + 5) == .success)
        }

        /// The publisher reads its pause state off the app lifecycle publisher, which is the only way a
        /// test can drive it.
        @MainActor
        private func sendLifecycle(background: Bool) {
            mockLifecycle.isInBackground = background
        }

        @MainActor
        @Test("the first multicast subscriber installs the observer and the last one removes it")
        func subscriberCountDrivesObserver() async throws {
            let sut = ApplicationRunLoopPublisher()
            var count = 0
            var deliveredOffMain = false
            var token: RegistrationToken? = sut.onOpportunity.subscribe(throttle: 0, trailing: true) {
                if !Thread.isMainThread { deliveredOffMain = true }
                count += 1
            }
            #expect(token != nil)
            #expect(sut.isObserving)
            await settle()
            try #require(count > 0)
            #expect(!deliveredOffMain)

            token = nil
            #expect(!sut.isObserving)
            await settle()
            let afterDrop = count
            await settle()
            #expect(count == afterDrop)
        }

        @MainActor
        @Test("a replay stop leaves the observer installed while another product still subscribes")
        func remainingSubscriberKeepsObserver() async throws {
            let sut = ApplicationRunLoopPublisher()
            let surveys = sut.onOpportunity.subscribe(throttle: 0, trailing: true) {}
            defer { withExtendedLifetime(surveys) {} }

            var replay: RegistrationToken? = sut.onOpportunity.subscribe(throttle: 0, trailing: true) {}
            #expect(replay != nil)
            #expect(sut.isObserving)

            // Replay's stop: drop its token.
            replay = nil
            #expect(sut.isObserving)
            await settle()
            #expect(sut.isObserving)
        }

        @MainActor
        @Test("demand recorded off the main thread converges on the latest value", arguments: [false, true])
        func offMainDemandConverges(subscribeLast: Bool) async throws {
            let sut = ApplicationRunLoopPublisher()
            var held: RegistrationToken?
            try runOffMain {
                if subscribeLast {
                    var token: RegistrationToken? = sut.onOpportunity.subscribe(throttle: 0) {}
                    token = nil
                    _ = token
                    held = sut.onOpportunity.subscribe(throttle: 0) {}
                } else {
                    held = sut.onOpportunity.subscribe(throttle: 0) {}
                    held = nil
                }
            }
            defer { withExtendedLifetime(held) {} }
            await settle()
            #expect(sut.isObserving == subscribeLast)
        }

        @MainActor
        @Test("one run-loop cycle yields at most one opportunity")
        func oneOpportunityPerCycle() throws {
            let sut = ApplicationRunLoopPublisher()

            // Both .beforeWaiting and .exit are observed, and a nested mode can exit more than once.
            sut.simulateActivity(.afterWaiting)
            sut.simulateActivity(.beforeWaiting)
            sut.simulateActivity(.exit)
            sut.simulateActivity(.beforeWaiting)
            #expect(sut.emittedOpportunities == 1)

            sut.simulateActivity(.afterWaiting)
            sut.simulateActivity(.exit)
            #expect(sut.emittedOpportunities == 2)
        }

        @MainActor
        @Test("background pauses delivery and foreground resumes it, repeatedly")
        func lifecyclePauseResumeCycles() async throws {
            let sut = ApplicationRunLoopPublisher()
            var count = 0
            let token = sut.onOpportunity.subscribe(throttle: 0, trailing: true) { count += 1 }
            defer { withExtendedLifetime(token) {} }
            defer { sendLifecycle(background: false) }

            try #require(sut.isObserving)
            for _ in 0 ..< 3 {
                sendLifecycle(background: true)
                await settle()
                let paused = count
                await settle()
                #expect(count == paused)

                sendLifecycle(background: false)
                await settle()
                #expect(count > paused)
            }
        }

        @MainActor
        @Test("a foreground event never installs an observer nothing asked for")
        func lifecycleDoesNotInstallWithoutDemand() async throws {
            let sut = ApplicationRunLoopPublisher()
            var token: RegistrationToken? = sut.onOpportunity.subscribe(throttle: 0, trailing: true) {}
            #expect(token != nil)
            try #require(sut.isObserving)
            token = nil
            try #require(!sut.isObserving)

            sendLifecycle(background: true)
            sendLifecycle(background: false)
            await settle()
            #expect(!sut.isObserving)
        }

        @MainActor
        @Test("a deallocated publisher stops delivering")
        func deallocationInvalidatesObserver() async throws {
            var count = 0
            var token: RegistrationToken?
            weak var weakSut: ApplicationRunLoopPublisher?
            do {
                let sut = ApplicationRunLoopPublisher()
                weakSut = sut
                token = sut.onOpportunity.subscribe(throttle: 0, trailing: true) { count += 1 }
                await settle()
                try #require(count > 0)
            }
            try #require(weakSut == nil)

            await settle()
            let afterDealloc = count
            await settle()
            #expect(count == afterDealloc)
            withExtendedLifetime(token) {}
        }

        @MainActor
        @Test("the subscriber's throttle still governs cadence")
        func throttleGovernsCadence() async throws {
            let sut = ApplicationRunLoopPublisher()
            var count = 0
            let token = sut.onOpportunity.subscribe(throttle: 60, trailing: true) { count += 1 }
            defer { withExtendedLifetime(token) {} }

            await settle(cycles: 15)
            // Many cycles, one open window.
            #expect(count == 1)
        }
    }

    /// The idle policy lives with replay, the only consumer that knows whether a frame changed, so a
    /// static screen can never slow anything else subscribed to the shared publisher.
    @Suite("Replay Capture Backoff", .serialized)
    final class PostHogReplayCaptureBackoffTest {
        @Test("backoff engages only after three consecutive unchanged frames")
        func backoffEngagesAfterThreeUnchangedFrames() {
            let sut = PostHogReplayCaptureBackoff()
            sut.setBaseInterval(10)

            sut.noteFrame(unchanged: true)
            sut.noteFrame(unchanged: true)
            #expect(sut.isInBackoffForTesting == false)
            #expect(sut.shouldCapture())

            sut.noteFrame(unchanged: true)
            #expect(sut.isInBackoffForTesting == true)
        }

        @Test("while backing off, captures are paced rather than stopped")
        func backoffPacesRatherThanStops() async throws {
            let sut = PostHogReplayCaptureBackoff()
            sut.setBaseInterval(0.05)
            for _ in 0 ..< 3 {
                sut.noteFrame(unchanged: true)
            }
            try #require(sut.isInBackoffForTesting)

            #expect(sut.shouldCapture() == false)

            try await Task.sleep(nanoseconds: 90 * NSEC_PER_MSEC)
            #expect(sut.shouldCapture())
        }

        @Test("the backoff interval doubles per further unchanged frame and caps at eight seconds")
        func backoffIntervalDoublesAndCaps() {
            let sut = PostHogReplayCaptureBackoff()
            sut.setBaseInterval(1)

            for _ in 0 ..< 3 {
                sut.noteFrame(unchanged: true)
            }
            #expect(sut.idleIntervalForTesting == 1)

            for expected in [2.0, 4.0, 8.0] {
                sut.noteFrame(unchanged: true)
                #expect(sut.idleIntervalForTesting == expected)
            }

            // Capped, not unbounded.
            sut.noteFrame(unchanged: true)
            sut.noteFrame(unchanged: true)
            #expect(sut.idleIntervalForTesting == 8)
        }

        @Test("a non-positive base interval still leaves the backoff in force")
        func nonPositiveBaseIntervalStillBacksOff() async throws {
            let sut = PostHogReplayCaptureBackoff()
            // `throttleDelay` is public and unvalidated; 0 must not silently disable the backoff.
            sut.setBaseInterval(0)
            for _ in 0 ..< 3 {
                sut.noteFrame(unchanged: true)
            }
            try #require(sut.isInBackoffForTesting)
            #expect(sut.idleIntervalForTesting > 0)
            #expect(sut.shouldCapture() == false)

            try await Task.sleep(nanoseconds: 120 * NSEC_PER_MSEC)
            #expect(sut.shouldCapture())
        }

        @Test("a changed frame restores the full rate immediately")
        func changedFrameRestoresFullRate() {
            let sut = PostHogReplayCaptureBackoff()
            sut.setBaseInterval(10)
            for _ in 0 ..< 4 {
                sut.noteFrame(unchanged: true)
            }
            #expect(sut.shouldCapture() == false)

            sut.noteFrame(unchanged: false)
            #expect(sut.isInBackoffForTesting == false)
            #expect(sut.idleIntervalForTesting == 10)
            #expect(sut.shouldCapture())
        }

        @Test("a touch leaves backoff immediately")
        func touchLeavesBackoff() {
            let sut = PostHogReplayCaptureBackoff()
            sut.setBaseInterval(10)
            for _ in 0 ..< 3 {
                sut.noteFrame(unchanged: true)
            }
            #expect(sut.shouldCapture() == false)

            sut.wake()
            #expect(sut.isInBackoffForTesting == false)
            #expect(sut.shouldCapture())
        }

        @Test("a screen that goes quiet and then changes again is still captured without a touch")
        func quietScreenThatChangesAgainIsStillCaptured() async throws {
            let sut = PostHogReplayCaptureBackoff()
            sut.setBaseInterval(0.02)

            // Deep backoff: 6 unchanged frames, so the interval has doubled several times.
            for _ in 0 ..< 6 {
                sut.noteFrame(unchanged: true)
            }
            try #require(sut.isInBackoffForTesting)
            try #require(sut.idleIntervalForTesting > 0.02)

            // No wake() anywhere in this test. Opportunities keep arriving, so the backoff must keep
            // letting captures through, which is the only way a self-driven change is ever seen.
            var captured = 0
            let deadline = Date().addingTimeInterval(5)
            while captured < 2, Date() < deadline {
                try await Task.sleep(nanoseconds: 20 * NSEC_PER_MSEC)
                if sut.shouldCapture() {
                    captured += 1
                }
            }
            #expect(captured >= 2)

            // That capture produced a changed frame, so the full rate comes back.
            sut.noteFrame(unchanged: false)
            #expect(sut.shouldCapture())
        }
    }

    @Suite("Run Loop Publisher Subscriber Isolation", .serialized)
    final class ApplicationRunLoopPublisherIsolationTest {
        private let mockLifecycle = MockApplicationLifecyclePublisher()
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
            DI.main.appLifecyclePublisher = mockLifecycle
        }

        deinit {
            DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
            server.stop()
        }

        private func getSut() -> PostHogSDK {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = true
            // Surveys subscribe to the same publisher by default; this test supplies its own
            // surveys-shaped subscriber so the count it asserts on is unambiguous.
            config._surveys = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.disableRemoteConfigForTesting = true
            config.captureApplicationLifecycleEvents = false

            let storage = PostHogStorage(config)
            storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])

            PostHogReplayIntegration.clearInstalls()
            return PostHogSDK.with(config)
        }

        /// Replay's pixel-dedup policy has nothing to say about whether a survey is due, so a static
        /// screen must not slow another subscriber sharing the publisher. Driven through the real
        /// integration and the real shared publisher: if the backoff were ever folded back into the
        /// publisher, engaging it here would starve the second subscriber and this would fail.
        @MainActor
        @Test("a real replay integration deep in backoff leaves another subscriber's cadence untouched")
        func replayBackoffDoesNotThrottleOtherSubscribers() async throws {
            let sut = getSut()
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())
            try #require(integration.isActive())
            await drainMain()
            // Replay's own subscription is what installed the shared observer.
            try #require(integration.isCaptureSchedulerObserving)

            // The very object the capture path consults, owned by the integration, not the publisher.
            let backoff = integration.captureBackoffForTesting
            for _ in 0 ..< 6 {
                backoff.noteFrame(unchanged: true)
            }
            try #require(backoff.isInBackoffForTesting)
            try #require(backoff.shouldCapture() == false)

            var surveyChecks = 0
            let surveys = DI.main.runLoopPublisher.onOpportunity.subscribe(throttle: 0, trailing: true) {
                surveyChecks += 1
            }
            defer { withExtendedLifetime(surveys) {} }

            for _ in 0 ..< 10 {
                try? await Task.sleep(nanoseconds: 20 * NSEC_PER_MSEC)
            }
            await drainMain()

            #expect(surveyChecks > 1)
            // Replay is still paced by its own policy, which is the saving this is meant to keep.
            #expect(backoff.isInBackoffForTesting)
            #expect(backoff.shouldCapture() == false)
        }

        @MainActor
        @Test("a new session leaves the backoff accrued in the previous one")
        func sessionChangeWakesBackoff() async throws {
            let sut = getSut()
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())
            try #require(integration.isActive())
            await drainMain()

            let backoff = integration.captureBackoffForTesting
            for _ in 0 ..< 6 {
                backoff.noteFrame(unchanged: true)
            }
            try #require(backoff.isInBackoffForTesting)
            try #require(backoff.shouldCapture() == false)

            sut.sessionManager.startSession()
            await drainMain()

            #expect(backoff.isInBackoffForTesting == false)
            #expect(backoff.shouldCapture())
        }
    }

    @Suite("Replay Capture Scheduling", .serialized)
    final class PostHogReplayCaptureSchedulingTest {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private func getSut(sampleRate: Double? = nil, eventTriggers: [String]? = nil) -> PostHogSDK {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = true
            // The observer is shared, and surveys subscribe to it by default. Leaving surveys off keeps
            // these assertions about replay's own demand.
            config._surveys = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.disableRemoteConfigForTesting = true

            let storage = PostHogStorage(config)
            var sessionRecording: [String: Any] = ["endpoint": "/s/"]
            if let sampleRate {
                sessionRecording["sampleRate"] = sampleRate
            }
            if let eventTriggers {
                sessionRecording["eventTriggers"] = eventTriggers
            }
            storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": sessionRecording])

            PostHogReplayIntegration.clearInstalls()
            return PostHogSDK.with(config)
        }

        @MainActor
        @Test("a sampled-out session never starts the capture scheduler")
        func sampledOutSessionDoesNotSchedule() async throws {
            let sut = getSut(sampleRate: 0)
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            #expect(integration.isActive() == false)
            #expect(integration.hasCaptureSubscription == false)
            await drainMain()
            #expect(integration.isCaptureSchedulerObserving == false)
        }

        @MainActor
        @Test("a pending event trigger defers the capture scheduler until the trigger fires")
        func pendingEventTriggerDefersScheduler() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            #expect(integration.isActive() == false)
            #expect(integration.hasCaptureSubscription == false)
            await drainMain()
            #expect(integration.isCaptureSchedulerObserving == false)

            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)
            #expect(integration.hasCaptureSubscription == true)
            await drainMain()
            #expect(integration.isCaptureSchedulerObserving == true)
        }
    }
#endif
