//
//  PostHogReplayCaptureTicker.swift
//  PostHog
//

#if os(iOS)
    import Foundation

    /// Decides which ticks of a fixed-rate timer attempt a capture.
    ///
    /// A screen that renders the same pixels every tick only costs a render, because the unchanged
    /// frame is dropped before upload. The backoff makes that idle case cheaper: every consecutive
    /// unchanged frame doubles the number of ticks skipped before the next attempt, up to
    /// `maximumSkips`. The first changed frame restores the base rate.
    struct PostHogReplayIdleBackoff {
        /// Ticks skipped after each further unchanged frame.
        private static let skipLadder = [1, 3, 7]

        /// Ceiling on skipped ticks, so a static screen renders once every 8 ticks.
        static let maximumSkips = skipLadder[skipLadder.count - 1]

        private var unchangedFrames = 0
        private var skipsRemaining = 0

        static func skips(afterUnchangedFrames count: Int) -> Int {
            guard count > 0 else { return 0 }
            return skipLadder[min(count, skipLadder.count) - 1]
        }

        mutating func shouldCapture() -> Bool {
            guard skipsRemaining > 0 else { return true }
            skipsRemaining -= 1
            return false
        }

        mutating func noteFrame(unchanged: Bool) {
            guard unchanged else {
                unchangedFrames = 0
                skipsRemaining = 0
                return
            }
            unchangedFrames += 1
            skipsRemaining = Self.skips(afterUnchangedFrames: unchangedFrames)
        }

        mutating func reset() {
            unchangedFrames = 0
            skipsRemaining = 0
        }
    }

    /// Asks for a snapshot on a timer, next to the layout-driven capture.
    ///
    /// Session replay captures when `UIView.layoutSublayers(of:)` runs, so a screen that changes its
    /// pixels without laying out any view — video, a Core Animation loop, a redraw-only update —
    /// produces no frame and replays as a still image until the next layout. The timer covers that
    /// gap, and `PostHogReplayIdleBackoff` keeps a static screen from rendering on every tick.
    final class PostHogReplayCaptureTicker {
        /// Floor for the tick rate, because `throttleDelay` is public and unvalidated.
        static let minimumInterval: TimeInterval = 0.1

        let tickInterval: TimeInterval

        private let onTick: () -> Void
        private let queue: DispatchQueue

        private let lock = NSLock()
        private var backoff = PostHogReplayIdleBackoff()
        private var timer: DispatchSourceTimer?

        /// - Parameter queue: where ticks are delivered. Capture reads the live view hierarchy, so
        ///   this is the main queue outside tests.
        init(interval: TimeInterval, queue: DispatchQueue = .main, onTick: @escaping () -> Void) {
            // max() also rejects a NaN interval: `NaN >= minimumInterval` is false.
            tickInterval = max(Self.minimumInterval, interval)
            self.queue = queue
            self.onTick = onTick
        }

        deinit {
            timer?.cancel()
        }

        func start() {
            stop()

            let newTimer = DispatchSource.makeTimerSource(queue: queue)
            newTimer.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
            newTimer.setEventHandler { [weak self] in
                self?.tick()
            }

            lock.withLock { timer = newTimer }
            newTimer.resume()
        }

        func stop() {
            let previousTimer = lock.withLock { () -> DispatchSourceTimer? in
                let existing = timer
                timer = nil
                return existing
            }
            previousTimer?.cancel()
        }

        /// Cancels the timer, rather than firing and discarding ticks, while the app is away.
        func pause() {
            stop()
        }

        func resume() {
            // A screen can change while the app is away, so start again at the base rate.
            lock.withLock { backoff.reset() }
            start()
        }

        /// Reports the outcome of a capture, from whichever queue produced the frame.
        func noteFrame(unchanged: Bool) {
            lock.withLock { backoff.noteFrame(unchanged: unchanged) }
        }

        private func tick() {
            guard lock.withLock({ backoff.shouldCapture() }) else { return }
            onTick()
        }
    }
#endif
