#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Screenshot-mode capture ticker")
    class PostHogReplayCaptureTickerTests {
        @Test("Backs off while frames stay unchanged")
        func backsOffWhileIdle() {
            var backoff = PostHogReplayIdleBackoff()

            // Tick 1 captures, and the frame is a duplicate, so one tick is skipped.
            #expect(backoff.shouldCapture())
            backoff.noteFrame(unchanged: true)
            #expect(!backoff.shouldCapture())
            #expect(backoff.shouldCapture())
            backoff.noteFrame(unchanged: true)

            // Three skipped ticks, then a capture.
            for _ in 0 ..< 3 {
                #expect(!backoff.shouldCapture())
            }
            #expect(backoff.shouldCapture())
            backoff.noteFrame(unchanged: true)

            // Seven skipped ticks: the ceiling.
            for _ in 0 ..< 7 {
                #expect(!backoff.shouldCapture())
            }
            #expect(backoff.shouldCapture())
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
            for _ in 0 ..< 10 {
                #expect(backoff.shouldCapture())
                backoff.noteFrame(unchanged: false)
            }
        }

        @Test("Ticks a screen that never lays out")
        func ticksWithoutLayout() async {
            let ticks = Atomic(0)
            let ticker = PostHogReplayCaptureTicker(
                interval: PostHogReplayCaptureTicker.minimumInterval,
                queue: DispatchQueue(label: "com.posthog.test.CaptureTicker")
            ) {
                ticks.mutate { $0 += 1 }
            }
            ticker.start()

            try? await Task.sleep(nanoseconds: 500_000_000)
            ticker.stop()

            #expect(ticks.value > 1)
        }

        @Test("A paused ticker asks for nothing")
        func pausedTickerIsQuiet() async {
            let ticks = Atomic(0)
            let ticker = PostHogReplayCaptureTicker(
                interval: PostHogReplayCaptureTicker.minimumInterval,
                queue: DispatchQueue(label: "com.posthog.test.PausedCaptureTicker")
            ) {
                ticks.mutate { $0 += 1 }
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

    private final class Atomic<T> {
        private let lock = NSLock()
        private var stored: T

        init(_ value: T) { stored = value }

        var value: T { lock.withLock { stored } }

        func mutate(_ change: (inout T) -> Void) {
            lock.withLock { change(&stored) }
        }
    }
#endif
