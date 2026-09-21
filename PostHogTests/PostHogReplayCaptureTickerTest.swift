#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Screenshot-mode capture ticker")
    class PostHogReplayCaptureTickerTests {
        /// Which of `tickCount` ticks capture, when every captured frame renders the same pixels.
        private func idleCaptureTicks(_ tickCount: Int) -> [Bool] {
            var backoff = PostHogReplayIdleBackoff()
            var captures: [Bool] = []
            for _ in 0 ..< tickCount {
                let captured = backoff.shouldCapture()
                if captured {
                    backoff.noteFrame(unchanged: true)
                }
                captures.append(captured)
            }
            return captures
        }

        @Test("Backs off while frames stay unchanged")
        func backsOffWhileIdle() {
            // A capture, then one skipped tick, then three, then the ceiling of seven.
            let expected: [Bool] = [true, false]
                + [true, false, false, false]
                + [true, false, false, false, false, false, false, false]
                + [true]

            #expect(idleCaptureTicks(expected.count) == expected)
        }

        @Test("Holds the ceiling instead of growing without bound")
        func holdsTheCeiling() {
            #expect(PostHogReplayIdleBackoff.skips(afterUnchangedFrames: 0) == 0)
            #expect(PostHogReplayIdleBackoff.skips(afterUnchangedFrames: 1) == 1)
            #expect(PostHogReplayIdleBackoff.skips(afterUnchangedFrames: 2) == 3)
            #expect(PostHogReplayIdleBackoff.skips(afterUnchangedFrames: 3) == 7)
            #expect(PostHogReplayIdleBackoff.skips(afterUnchangedFrames: 40) == PostHogReplayIdleBackoff.maximumSkips)
        }

        @Test("A changed frame restores the base rate")
        func changedFrameRestoresBaseRate() {
            var backoff = PostHogReplayIdleBackoff()
            for _ in 0 ..< 4 {
                backoff.noteFrame(unchanged: true)
            }
            backoff.noteFrame(unchanged: false)

            // Video and animation change every frame, so every tick must capture.
            var captures: [Bool] = []
            for _ in 0 ..< 10 {
                captures.append(backoff.shouldCapture())
                backoff.noteFrame(unchanged: false)
            }

            #expect(captures.allSatisfy { $0 })
        }

        @Test("Ticks a screen that never lays out")
        func ticksWithoutLayout() async {
            let ticks = TickCounter()
            let ticker = PostHogReplayCaptureTicker(
                interval: PostHogReplayCaptureTicker.minimumInterval,
                queue: DispatchQueue(label: "com.posthog.test.CaptureTicker")
            ) {
                ticks.increment()
            }
            ticker.start()

            try? await Task.sleep(nanoseconds: 500_000_000)
            ticker.stop()

            #expect(ticks.value > 1)
        }

        @Test("A paused ticker asks for nothing")
        func pausedTickerIsQuiet() async {
            let ticks = TickCounter()
            let ticker = PostHogReplayCaptureTicker(
                interval: PostHogReplayCaptureTicker.minimumInterval,
                queue: DispatchQueue(label: "com.posthog.test.PausedCaptureTicker")
            ) {
                ticks.increment()
            }
            ticker.start()
            ticker.pause()
            let ticksWhenPaused = ticks.value

            try? await Task.sleep(nanoseconds: 500_000_000)
            ticker.stop()

            #expect(ticks.value == ticksWhenPaused)
        }

        @Test("A short interval is clamped")
        func clampsShortInterval() {
            let ticker = PostHogReplayCaptureTicker(interval: 0) {}

            #expect(ticker.tickInterval == PostHogReplayCaptureTicker.minimumInterval)
        }
    }

    private final class TickCounter {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.withLock { count }
        }

        func increment() {
            lock.withLock { count += 1 }
        }
    }
#endif
