import Foundation

/// Delegate protocol for controlling session replay buffering behavior
//  This will be usually the `PostHogReplayIntegation`
///
/// The replay queue is passive: it asks `shouldBufferSnapshot()` on every `add()` and checks `isBuffering` on `flush()`,
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

    /// The mask generation of the frame being queued on the calling thread, nil when the event carries no frame.
    var currentCaptureMaskingGeneration: Int? { get }

    /// Moves each time a mask flag turns on. A frame stamped with an older value is stale.
    var currentMaskingGeneration: Int { get }

    /// Decides where `queue.add()` routes a snapshot: `true` buffers it. Unlike `isBuffering`, a delegate
    /// may record that the session went out unheld, in the same decision.
    func shouldBufferSnapshot() -> Bool
}

extension PostHogReplayBufferDelegate {
    var currentCaptureMaskingGeneration: Int? { nil }
    var currentMaskingGeneration: Int { 0 }

    func shouldBufferSnapshot() -> Bool {
        isBuffering
    }
}
