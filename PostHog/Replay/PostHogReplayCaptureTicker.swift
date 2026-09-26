//
//  PostHogReplayCaptureTicker.swift
//  PostHog
//

#if os(iOS)
    import Foundation

    /// Asks for a snapshot on a timer, next to the layout-driven capture.
    ///
    /// Session replay captures when `UIView.layoutSublayers(of:)` runs, so a screen that changes its
    /// pixels without laying out any view (a Core Animation loop, a redraw-only update) produces no
    /// frame until the next layout. The same gap leaves a recording on the previous screen when the
    /// capture after a navigation lands mid-transition and is dropped. The timer covers both.
    ///
    /// The timer shares `throttleDelay` with the layout trigger: both claim a capture through
    /// `claimCapture()`, which refuses when either trigger started one within the last interval.
    /// After `idleFrameLimit` unchanged frames, or ticks that produced no frame, in a row the timer
    /// stops, and the next layout or touch (`wake()`) starts it again. So a static screen stops
    /// rendering, and so does a redraw-only change that comes after the timer stopped, until the
    /// next layout or touch.
    final class PostHogReplayCaptureTicker {
        /// Bounds for the tick rate, because `throttleDelay` is public and unvalidated. A huge
        /// interval traps when the timer converts it to nanoseconds.
        static let minimumInterval: TimeInterval = 0.1
        static let maximumInterval: TimeInterval = 3600

        /// Unchanged frames, or ticks without a frame, in a row before the timer stops.
        static let idleFrameLimit = 3

        let tickInterval: TimeInterval

        private let onTick: () -> Void
        private let queue: DispatchQueue
        private let now: () -> TimeInterval

        private let lock = NSLock()
        private var timer: DispatchSourceTimer?
        private var isStarted = false
        private var isPaused = false
        private var unchangedFrames = 0
        private var ticksWithoutFrame = 0
        private var lastCaptureAt: TimeInterval?

        /// - Parameter queue: where ticks are delivered. Capture reads the live view hierarchy, so
        ///   this is the main queue outside tests.
        init(
            interval: TimeInterval,
            queue: DispatchQueue = .main,
            // Monotonic, so a wall-clock change can't make a frame look recent forever.
            now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
            onTick: @escaping () -> Void
        ) {
            // max() also rejects a NaN interval: `NaN >= minimumInterval` is false.
            tickInterval = min(Self.maximumInterval, max(Self.minimumInterval, interval))
            self.queue = queue
            self.now = now
            self.onTick = onTick
        }

        deinit {
            timer?.cancel()
        }

        var isRunning: Bool {
            lock.withLock { timer != nil }
        }

        func start() {
            lock.withLock {
                isStarted = true
                isPaused = false
                resetIdleCounts()
                scheduleTimer()
            }
        }

        func stop() {
            lock.withLock {
                isStarted = false
                cancelTimer()
            }
        }

        /// Cancels the timer, rather than firing and discarding ticks, while the app is away.
        func pause() {
            lock.withLock {
                isPaused = true
                cancelTimer()
            }
        }

        func resume() {
            lock.withLock {
                isPaused = false
                resetIdleCounts()
                if isStarted {
                    scheduleTimer()
                }
            }
        }

        /// Restarts a timer that stopped on an idle screen. Called on layout and touch.
        func wake() {
            lock.withLock {
                resetIdleCounts()
                if isStarted, !isPaused, timer == nil {
                    scheduleTimer()
                }
            }
        }

        /// Reports a rendered frame, from either trigger and from whichever queue produced it.
        func noteFrame(unchanged: Bool) {
            lock.withLock {
                ticksWithoutFrame = 0
                guard unchanged else {
                    unchangedFrames = 0
                    return
                }
                unchangedFrames += 1
                if unchangedFrames >= Self.idleFrameLimit {
                    cancelTimer()
                }
            }
        }

        /// Claims the next capture for the layout trigger. Returns false when either trigger started
        /// one within the last interval, since the running timer picks the change up.
        func claimCapture() -> Bool {
            lock.withLock { claimCaptureLocked() }
        }

        func tick() {
            let shouldCapture = lock.withLock { () -> Bool in
                guard timer != nil else { return false }
                // Capture can be gated off (flag, sampling, no active window), and then a tick
                // never produces a frame. Stop rather than wake the app every interval.
                if ticksWithoutFrame >= Self.idleFrameLimit {
                    cancelTimer()
                    return false
                }
                guard claimCaptureLocked() else { return false }
                ticksWithoutFrame += 1
                return true
            }
            if shouldCapture {
                onTick()
            }
        }

        // Callers hold `lock`.
        private func claimCaptureLocked() -> Bool {
            let current = now()
            // The slack matches the timer's 10% leeway. Without it, a tick landing just short of
            // a full interval after a layout capture would skip and double the gap.
            if let lastCaptureAt, current - lastCaptureAt < tickInterval * 0.9 {
                return false
            }
            lastCaptureAt = current
            return true
        }

        private func resetIdleCounts() {
            unchangedFrames = 0
            ticksWithoutFrame = 0
        }

        private func scheduleTimer() {
            cancelTimer()
            let newTimer = DispatchSource.makeTimerSource(queue: queue)
            let leeway = DispatchTimeInterval.milliseconds(Int(tickInterval * 100))
            newTimer.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: leeway)
            newTimer.setEventHandler { [weak self] in
                self?.tick()
            }
            timer = newTimer
            newTimer.resume()
        }

        private func cancelTimer() {
            timer?.cancel()
            timer = nil
        }
    }
#endif
