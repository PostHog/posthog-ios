#if os(iOS)
    import Foundation

    /// Publishes capture opportunities from the main run loop, so nothing has to swizzle
    /// `UIView.layoutSublayers(of:)` to learn that the screen may have changed.
    ///
    /// An opportunity is a hint that capture is worth considering, not proof that a new frame exists.
    /// Dedup, throttling and in-flight protection stay where they already live: the throttle on
    /// `onOpportunity` and the renderer behind it. Nothing here is per-subscriber, so one subscriber's
    /// capture policy cannot slow another's.
    protocol RunLoopOpportunityPublishing: AnyObject {
        var onOpportunity: PostHogThrottledMulticastCallback<Void> { get }

        /// Whether an observer is currently registered. Main-confined; read it from the main thread.
        var isObserving: Bool { get }
    }

    final class ApplicationRunLoopPublisher: RunLoopOpportunityPublishing {
        static let shared = ApplicationRunLoopPublisher()

        var onOpportunity: PostHogThrottledMulticastCallback<Void> { callbacks }
        private var callbacks: PostHogThrottledMulticastCallback<Void>!

        // Main-confined. Read and written only from blocks already running on the main thread, which is
        // also where the observer callback runs, so the hot path takes no lock.
        private var observer: CFRunLoopObserver?
        private var didConsiderCurrentCycle = false

        var isObserving: Bool {
            observer != nil
        }

        init() {
            // Initialize before publication; Swift lazy properties are not safe on concurrent first access.
            // The count is not captured: `reconcile()` reads the multicast's live count instead, so a
            // hop that lands out of order still resolves to the latest demand.
            callbacks = PostHogThrottledMulticastCallback<Void> { [weak self] _ in
                self?.reconcileOnMain()
            }
        }

        deinit {
            // The run loop retains the observer, so it outlives us unless it is invalidated here.
            // Reading the main-confined field off main is safe only here: `deinit` runs after the last
            // reference is gone, so nothing else can be mutating it, and invalidating a local copy
            // needs no hop back to main — a hop would have to capture `self` and resurrect it.
            // Invalidate alone is enough; it also removes the observer from every run loop it is in.
            if let installed = observer {
                CFRunLoopObserverInvalidate(installed)
            }
        }

        // MARK: - Lifecycle

        private func onMain(_ body: @escaping (ApplicationRunLoopPublisher) -> Void) {
            if Thread.isMainThread {
                body(self)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    body(self)
                }
            }
        }

        private func reconcileOnMain() {
            onMain { publisher in publisher.reconcile() }
        }

        /// Reconciles the observer against the latest recorded demand. Idempotent, so repeated or
        /// reordered hops converge instead of racing.
        private func reconcile() {
            let wanted = callbacks.subscriberCount > 0

            guard wanted else {
                uninstall()
                return
            }
            guard observer == nil else { return }

            didConsiderCurrentCycle = false
            install()
        }

        private func install() {
            // CFRunLoopObserver callbacks for the same activity fire in ascending order, and Core
            // Animation's commit observer sits at 2_000_000. A larger order therefore runs after that
            // commit in practice — the relative ordering of another framework's observer is not a
            // documented guarantee, so capture must not depend on it for correctness.
            let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting, .exit]
            guard let observer = CFRunLoopObserverCreateWithHandler(
                nil,
                activities.rawValue,
                true,
                2_100_000,
                { [weak self] _, activity in
                    self?.handle(activity)
                }
            ) else {
                // Nothing retries this: without the observer no subscriber is ever offered another
                // capture opportunity, so say so rather than failing silently.
                hedgeLog("[Run Loop] Could not create the main run loop observer - session replay and surveys get no more capture opportunities")
                return
            }

            self.observer = observer
            // commonModes so tracking modes (scrolling, gestures) are covered as well as the default mode.
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        private func uninstall() {
            guard let observer else { return }
            self.observer = nil
            didConsiderCurrentCycle = false
            // Invalidate removes the observer from every run loop it was added to, so an explicit
            // CFRunLoopRemoveObserver first would be redundant.
            CFRunLoopObserverInvalidate(observer)
        }

        // MARK: - Observer callback

        private func handle(_ activity: CFRunLoopActivity) {
            // Waking up begins a new cycle. `.beforeWaiting` and `.exit` can both land in one cycle, so
            // the flag keeps that cycle to a single opportunity.
            if activity.contains(.afterWaiting) {
                didConsiderCurrentCycle = false
                return
            }
            // A backgrounded app has nothing to capture for anybody. Read rather than tracked, so a
            // publisher installed mid-background is paused without waiting for the next notification.
            guard !DI.main.appLifecyclePublisher.isInBackground, !didConsiderCurrentCycle else { return }
            didConsiderCurrentCycle = true
            #if TESTING
                emittedOpportunities += 1
            #endif
            onOpportunity.invoke(())
        }

        #if TESTING
            /// Feeds the callback directly, bypassing the run loop, so per-cycle dedup can be driven
            /// deterministically from a test.
            func simulateActivity(_ activity: CFRunLoopActivity) {
                handle(activity)
            }

            /// Counts emitted opportunities at the source, so a test can assert without waiting on the
            /// multicast's main-queue delivery.
            private(set) var emittedOpportunities = 0
        #endif
    }
#endif
