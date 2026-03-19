import Foundation

/// A replay queue that wraps a `PostHogQueue` (for actual API sends) and a
/// `PostHogReplayBufferQueue` (for buffering snapshots until minimum session
/// duration is met).
///
/// The queue is passive — it delegates all buffering decisions to a
/// `PostHogReplayBufferDelegate`. When `delegate.isBuffering` is true,
/// snapshots are routed to the buffer and `flush()` calls are suppressed.
class PostHogReplayQueue {
    private let innerQueue: PostHogQueue
    private let bufferQueue: PostHogReplayBufferQueue

    weak var bufferDelegate: PostHogReplayBufferDelegate?

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
            innerQueue = PostHogQueue(config, storage, api, .snapshot, reachability)
            bufferQueue = PostHogReplayBufferQueue(queue: storage.url(forKey: .replayBufferQueue))
        }
    #else
        init(_ config: PostHogConfig,
             _ storage: PostHogStorage,
             _ api: PostHogApi)
        {
            innerQueue = PostHogQueue(config, storage, api, .snapshot)
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
        if bufferDelegate?.isBuffering == true {
            guard let data = toJSONData(event.toJSON()) else {
                hedgeLog("Tried to buffer unserialisable PostHogEvent")
                return
            }
            bufferQueue.add(data)
            hedgeLog("Buffered replay event '\(event.event)'. Buffer depth: \(bufferQueue.depth)")
            bufferDelegate?.replayQueueDidBufferSnapshot(self)
        } else {
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
    func migrateBufferToQueue() {
        let migratedCount = bufferQueue.depth
        guard migratedCount > 0 else {
            hedgeLog("No buffered replay events to migrate")
            return
        }

        bufferQueue.migrateAll(to: innerQueue.fileQueue)
        hedgeLog("Migrated \(migratedCount) buffered replay events to replay queue. Queue depth: \(innerQueue.depth)")
        innerQueue.flushIfOverThreshold()
    }

    /// Discards all buffered replay events.
    func clearBuffer() {
        bufferQueue.clear()
        hedgeLog("Replay buffer cleared")
    }

    /// Prunes buffer items older than the given duration from the newest item.
    func pruneBuffer(olderThan duration: TimeInterval) {
        bufferQueue.pruneOlderThan(duration: duration)
    }

    /// Internal, used for testing
    func clear() {
        innerQueue.clear()
        bufferQueue.clear()
    }
}
