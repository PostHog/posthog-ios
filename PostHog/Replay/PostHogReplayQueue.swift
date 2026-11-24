import Foundation

/// A replay queue that wraps a `PostHogQueue` (for actual API sends) and a
/// `PostHogReplayBufferQueue` (for buffering snapshots until minimum session
/// duration is met).
///
/// The queue is passive — it delegates all buffering decisions to a
/// `PostHogReplayBufferDelegate`. When `delegate.isBuffering` is true,
/// snapshots are routed to the buffer and `flush()` calls are suppressed.
class PostHogReplayQueue {
    private let innerQueue: PostHogQueue<PostHogEvent>
    private let bufferQueue: PostHogReplayBufferQueue
    private let bufferIOQueue = DispatchQueue(label: "com.posthog.ReplayBufferIO",
                                              target: .global(qos: .utility))

    private let bufferLock = NSLock()
    private var bufferedMaskingGeneration: Int?

    weak var bufferDelegate: PostHogReplayBufferDelegate? {
        // A generation only means something to the delegate that issued it.
        didSet { bufferLock.withLock { bufferedMaskingGeneration = nil } }
    }

    /// The time span of buffered snapshots (oldest to newest).
    var bufferDuration: TimeInterval? {
        bufferQueue.bufferDuration
    }

    /// Number of events currently in the buffer.
    var bufferDepth: Int {
        bufferQueue.depth
    }

    /// Number of events in the inner (real) replay queue.
    var depth: Int {
        innerQueue.depth
    }

    #if !os(watchOS)
        init(_ config: PostHogConfig,
             _ storage: PostHogStorage,
             _ api: PostHogApi,
             _ reachability: Reachability?)
        {
            innerQueue = PostHogQueue(config, storage, .snapshot(api: api), reachability)
            bufferQueue = PostHogReplayBufferQueue(queue: storage.url(forKey: .replayBufferQueue))
        }
    #else
        init(_ config: PostHogConfig,
             _ storage: PostHogStorage,
             _ api: PostHogApi)
        {
            innerQueue = PostHogQueue(config, storage, .snapshot(api: api))
            bufferQueue = PostHogReplayBufferQueue(queue: storage.url(forKey: .replayBufferQueue))
        }
    #endif

    func start(disableReachabilityForTesting: Bool,
               disableQueueTimerForTesting: Bool)
    {
        innerQueue.start(disableReachabilityForTesting: disableReachabilityForTesting,
                         disableQueueTimerForTesting: disableQueueTimerForTesting)
        // no need to start/stop buffer queue
    }

    func stop() {
        innerQueue.stop()
        // no need to start/stop buffer queue
    }

    func add(_ event: PostHogEvent) {
        let frameGeneration = bufferDelegate?.currentCaptureMaskingGeneration
        func isStale() -> Bool {
            frameGeneration != nil && frameGeneration != bufferDelegate?.currentMaskingGeneration
        }
        func logStale() {
            hedgeLog("Dropped replay event '\(event.event)': a mask flag turned on after it was captured")
        }

        if bufferDelegate?.isBuffering == true {
            guard let data = toJSONData(event.toJSON()) else {
                hedgeLog("Tried to buffer unserialisable PostHogEvent")
                return
            }
            let depth: Int? = bufferLock.withLock {
                if isStale() { return nil }
                bufferQueue.add(data)
                // Keep the oldest: a fresh frame must not make a stale window look current.
                bufferedMaskingGeneration = bufferedMaskingGeneration ?? bufferDelegate?.currentMaskingGeneration
                return bufferQueue.depth
            }
            guard let depth else {
                logStale()
                return
            }
            hedgeLog("Buffered replay event '\(event.event)'. Buffer depth: \(depth)")
            bufferDelegate?.replayQueueDidBufferSnapshot(self)
        } else {
            if isStale() {
                logStale()
                return
            }
            innerQueue.add(event)
        }
    }

    func flush() {
        if bufferDelegate?.isBuffering == true {
            hedgeLog("Replay queue flush suppressed — still buffering")
            return
        }
        innerQueue.flush()
    }

    /// Migrates all buffered items to the inner (real) replay queue.
    /// Both on-disk files and in-memory items are transferred.
    ///
    /// If called from the main thread, migration is offloaded to a utility queue
    /// to avoid blocking rendering. On background threads migration executes inline.
    func migrateBufferToQueue() {
        performBufferOperation { [weak self] in
            self?.migrateBufferToQueueNow()
        }
    }

    /// Discards all buffered replay events.
    ///
    /// If called from the main thread, clear is offloaded to a utility queue to
    /// avoid blocking rendering. On background threads clear executes inline.
    func clearBuffer() {
        performBufferOperation { [weak self] in
            self?.clearBufferNow()
        }
    }

    private func performBufferOperation(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            bufferIOQueue.async(execute: operation)
            return
        }

        operation()
    }

    private func migrateBufferToQueueNow() {
        let migrated: Int = bufferLock.withLock {
            if let buffered = bufferedMaskingGeneration,
               let delegate = bufferDelegate,
               buffered != delegate.currentMaskingGeneration
            {
                hedgeLog("Replay buffer migration skipped: a mask flag turned on and the buffer is about to be cleared")
                return 0
            }

            let migratedCount = bufferQueue.depth
            guard migratedCount > 0 else {
                hedgeLog("No buffered replay events to migrate")
                return 0
            }

            bufferQueue.migrateAll(to: innerQueue.fileQueue)
            bufferedMaskingGeneration = nil
            hedgeLog("Migrated \(migratedCount) buffered replay events to replay queue. Queue depth: \(innerQueue.depth)")
            return migratedCount
        }

        if migrated > 0 {
            innerQueue.flushIfOverThreshold()
        }
    }

    private func clearBufferNow() {
        bufferLock.withLock {
            bufferQueue.clear()
            bufferedMaskingGeneration = nil
        }
        hedgeLog("Replay buffer cleared")
    }

    /// Internal, used for testing
    func clear() {
        innerQueue.clear()
        bufferLock.withLock {
            bufferQueue.clear()
            bufferedMaskingGeneration = nil
        }
    }
}
