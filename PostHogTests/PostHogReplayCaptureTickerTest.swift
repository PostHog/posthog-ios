#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Screenshot-mode capture ticker")
    class PostHogReplayCaptureTickerTests {
        /// A ticker whose timer never fires during a test, so `tick()` is driven by hand.
        private func manualTicker(clock: TestClock, ticks: TickCounter) -> PostHogReplayCaptureTicker {
            PostHogReplayCaptureTicker(
                interval: 60,
                queue: DispatchQueue(label: "com.posthog.test.ManualCaptureTicker"),
                now: { clock.now }
            ) {
                ticks.increment()
            }
        }

        @Test("Skips a tick right after a layout capture started")
        func sharesTheThrottleWithLayoutCapture() {
            let clock = TestClock()
            let ticks = TickCounter()
            let ticker = manualTicker(clock: clock, ticks: ticks)
            ticker.start()

            #expect(ticker.claimCapture())
            clock.advance(3)
            ticker.tick()
            #expect(ticks.value == 0)

            clock.advance(57)
            ticker.tick()
            #expect(ticks.value == 1)
        }

        @Test("Stops after unchanged frames and restarts on wake")
        func stopsWhenIdle() {
            let clock = TestClock()
            let ticks = TickCounter()
            let ticker = manualTicker(clock: clock, ticks: ticks)
            ticker.start()

            for _ in 0 ..< PostHogReplayCaptureTicker.idleFrameLimit {
                #expect(ticker.isRunning)
                ticker.noteFrame(unchanged: true)
            }
            #expect(!ticker.isRunning)

            clock.advance(120)
            ticker.tick()
            #expect(ticks.value == 0)

            ticker.wake()
            #expect(ticker.isRunning)
            ticker.tick()
            #expect(ticks.value == 1)
        }

        @Test("A changed frame resets the idle count")
        func changedFrameKeepsItRunning() {
            let clock = TestClock()
            let ticker = manualTicker(clock: clock, ticks: TickCounter())
            ticker.start()

            for _ in 0 ..< 10 {
                ticker.noteFrame(unchanged: true)
                ticker.noteFrame(unchanged: false)
            }

            #expect(ticker.isRunning)
        }

        @Test("Wake does nothing once stopped or paused")
        func wakeRespectsStopAndPause() {
            let ticker = manualTicker(clock: TestClock(), ticks: TickCounter())
            ticker.start()

            ticker.pause()
            ticker.wake()
            #expect(!ticker.isRunning)

            ticker.resume()
            #expect(ticker.isRunning)

            ticker.stop()
            ticker.wake()
            ticker.resume()
            #expect(!ticker.isRunning)
        }

        @Test("Refuses the layout trigger for most of an interval after a tick")
        func layoutWaitsForTheInterval() {
            let clock = TestClock()
            let ticks = TickCounter()
            let ticker = manualTicker(clock: clock, ticks: ticks)
            ticker.start()

            ticker.tick()
            #expect(ticks.value == 1)
            clock.advance(53)
            #expect(!ticker.claimCapture())

            clock.advance(1)
            #expect(ticker.claimCapture())
        }

        @Test("Stops when ticks keep producing no frame")
        func stopsWhenCaptureIsGatedOff() {
            let clock = TestClock()
            let ticks = TickCounter()
            let ticker = manualTicker(clock: clock, ticks: ticks)
            ticker.start()

            for _ in 0 ... PostHogReplayCaptureTicker.idleFrameLimit {
                clock.advance(60)
                ticker.tick()
            }

            #expect(ticks.value == PostHogReplayCaptureTicker.idleFrameLimit)
            #expect(!ticker.isRunning)
        }

        @Test("A frame between ticks keeps it running")
        func frameResetsTicksWithoutFrame() {
            let clock = TestClock()
            let ticker = manualTicker(clock: clock, ticks: TickCounter())
            ticker.start()

            for _ in 0 ..< 10 {
                clock.advance(60)
                ticker.tick()
                ticker.noteFrame(unchanged: false)
            }

            #expect(ticker.isRunning)
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

        @Test("An out-of-range interval is clamped")
        func clampsInterval() {
            #expect(PostHogReplayCaptureTicker(interval: 0) {}.tickInterval == PostHogReplayCaptureTicker.minimumInterval)
            #expect(PostHogReplayCaptureTicker(interval: .nan) {}.tickInterval == PostHogReplayCaptureTicker.minimumInterval)
            #expect(PostHogReplayCaptureTicker(interval: 1e11) {}.tickInterval == PostHogReplayCaptureTicker.maximumInterval)
        }
    }

    private final class TestClock {
        private let lock = NSLock()
        private var uptime: TimeInterval = 1000

        var now: TimeInterval {
            lock.withLock { uptime }
        }

        func advance(_ seconds: TimeInterval) {
            lock.withLock { uptime += seconds }
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
