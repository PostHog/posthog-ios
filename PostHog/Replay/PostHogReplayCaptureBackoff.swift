#if os(iOS)
    import Foundation

    /// Replay's own capture cadence policy, kept out of the shared run-loop publisher so it cannot
    /// throttle anything else subscribed there.
    ///
    /// A screen that keeps rendering identical pixels must get cheap, but it must never become
    /// unreachable: with no layout hook there is no external signal that content started moving again,
    /// so an idle screen backs off progressively instead of stopping until a touch.
    final class PostHogReplayCaptureBackoff {
        private static let unchangedFramesBeforeBackoff = 3
        private static let maxIdleInterval: TimeInterval = 8
        private static let maxDoublings = 20
        /// `throttleDelay` is public and unvalidated. A base of 0 would make every backoff window
        /// elapse instantly, silently disabling the backoff, so the base never goes below this.
        private static let minimumBaseInterval: TimeInterval = 0.05

        private let lock = NSLock()
        private var baseInterval: TimeInterval = 1
        private var unchangedFrames = 0
        private var lastEmit: UInt64 = 0

        /// The cadence backoff starts from, which is replay's own throttle interval.
        func setBaseInterval(_ interval: TimeInterval) {
            lock.withLock {
                baseInterval = max(interval, Self.minimumBaseInterval)
                unchangedFrames = 0
            }
        }

        /// Reports a rendered frame's dedup verdict, from whichever queue produced it.
        func noteFrame(unchanged: Bool) {
            lock.withLock {
                guard unchanged else {
                    unchangedFrames = 0
                    return
                }
                unchangedFrames += 1
                if unchangedFrames == Self.unchangedFramesBeforeBackoff {
                    lastEmit = DispatchTime.now().uptimeNanoseconds
                }
            }
        }

        /// Leaves backoff early. Called on touch, as an optimisation rather than the only escape.
        func wake() {
            lock.withLock { unchangedFrames = 0 }
        }

        /// Whether this opportunity is worth rendering a frame for. Monotonic, so a wall-clock jump
        /// cannot strand a backed-off screen past its next capture.
        func shouldCapture() -> Bool {
            lock.withLock {
                guard isBackingOff else { return true }
                let now = DispatchTime.now().uptimeNanoseconds
                let elapsed = now >= lastEmit ? now - lastEmit : 0
                guard TimeInterval(elapsed) / TimeInterval(NSEC_PER_SEC) >= idleInterval else { return false }
                lastEmit = now
                return true
            }
        }

        private var isBackingOff: Bool {
            unchangedFrames >= Self.unchangedFramesBeforeBackoff
        }

        private var idleInterval: TimeInterval {
            guard unchangedFrames > Self.unchangedFramesBeforeBackoff else { return baseInterval }
            let doublings = min(unchangedFrames - Self.unchangedFramesBeforeBackoff, Self.maxDoublings)
            return min(baseInterval * pow(2, Double(doublings)), Self.maxIdleInterval)
        }

        #if TESTING
            var isInBackoffForTesting: Bool { lock.withLock { isBackingOff } }

            var idleIntervalForTesting: TimeInterval { lock.withLock { idleInterval } }
        #endif
    }
#endif
