import Foundation

/// Delegate protocol for controlling session replay buffering behavior
//  This will be usually the `PostHogReplayIntegation`
///
/// The replay queue is passive: it checks `isBuffering` on every `add()` and `flush()`,
/// and notifies the delegate after buffering a snapshot. The delegate (replay integration)
/// has full control over:
/// 1. Whether we are buffering (`isBuffering`)
/// 2. When to flush buffer to real queue (calls `replayQueue.migrateBufferToQueue()`)
/// 3. When to clear the buffer (calls `replayQueue.clearBuffer()`)
protocol PostHogReplayBufferDelegate: AnyObject {
    /// Whether the replay queue should buffer snapshots instead of sending directly.
    /// Checked on every `queue.add()` and `queue.flush()`.
    var isBuffering: Bool { get }

    /// Called after a snapshot was added to the buffer.
    /// The delegate should check threshold conditions and call
    /// `replayQueue.migrateBufferToQueue()` when the minimum duration has been met.
    /// This will copy temp buffer queue to the real replay queue
    func replayQueueDidBufferSnapshot(_ replayQueue: PostHogReplayQueue)
}
