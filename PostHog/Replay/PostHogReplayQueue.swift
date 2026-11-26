import Foundation

/// A replay queue that wraps a `PostHogQueue` (for actual API sends) and a
/// `PostHogReplayBufferQueue` (for buffering snapshots until minimum session
/// duration is met).
///
/// The queue is passive — it delegates all buffering decisions to a
/// `PostHogReplayBufferDelegate`: `add()` routes a snapshot to the buffer when
/// `delegate.shouldBufferSnapshot()` is true, and `flush()` is suppressed while `delegate.isBuffering` is.
class PostHogReplayQueue {
    private let innerQueue: PostHogQueue<PostHogEvent>
    private let bufferQueue: PostHogReplayBufferQueue
    private let bufferIOQueue = DispatchQueue(label: "com.posthog.ReplayBufferIO",
                                              target: .global(qos: .utility))

    weak var bufferDelegate: PostHogReplayBufferDelegate?

    #if TESTING
        /// Runs after `add` routes a snapshot to the real queue and before it writes it.
        var onDirectRouteForTesting: (() -> Void)?
    #endif

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
        if bufferDelegate?.shouldBufferSnapshot() == true {
            guard let data = toJSONData(event.toJSON()) else {
                hedgeLog("Tried to buffer unserialisable PostHogEvent")
                return
            }
            bufferQueue.add(data)
            hedgeLog("Buffered replay event '\(event.event)'. Buffer depth: \(bufferQueue.depth)")
            bufferDelegate?.replayQueueDidBufferSnapshot(self)
        } else {
            #if TESTING
                onDirectRouteForTesting?()
            #endif
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
    /// Both on-disk files and in-memory items are transferred. The items are taken now, so a
    /// later `clearBuffer()` can't discard them and a snapshot added after this call stays buffered.
    ///
    /// If called from the main thread, the files are moved on a utility queue
    /// to avoid blocking rendering. On background threads they are moved inline.
    func migrateBufferToQueue() {
        let batch = bufferQueue.removeAll()
        guard !batch.isEmpty else {
            hedgeLog("No buffered replay events to migrate")
            return
        }
        performBufferOperation { [bufferQueue, innerQueue] in
            bufferQueue.migrate(batch, to: innerQueue.fileQueue)
            hedgeLog("Migrated \(batch.count) buffered replay events to replay queue. Queue depth: \(innerQueue.depth)")
            innerQueue.flushIfOverThreshold()
        }
    }

    /// Discards all buffered replay events. A snapshot added after this call is kept, so a new
    /// session's first snapshots can't be lost to the previous session's clear.
    ///
    /// If called from the main thread, the files are deleted on a utility queue to
    /// avoid blocking rendering. On background threads they are deleted inline.
    func clearBuffer() {
        let removed = bufferQueue.removeAll()
        performBufferOperation { [bufferQueue] in
            bufferQueue.delete(removed)
            hedgeLog("Replay buffer cleared")
        }
    }

    private func performBufferOperation(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            bufferIOQueue.async(execute: operation)
            return
        }

        operation()
    }

    /// Internal, used for testing
    func clear() {
        innerQueue.clear()
        bufferQueue.clear()
    }
}
