//
//  QueueEndpoint.swift
//  PostHog
//

import Foundation

/// Per-wire spec consumed by the generic `PostHogQueue<Record>`.
///
/// Encapsulates everything that differs between the events `/batch`, replay
/// `/snapshot`, and logs `/i/v1/logs` endpoints — disk codec, payload assembly,
/// retry policy, and adaptive-cap policy — so the queue itself stays
/// record-type-agnostic. Implemented as a struct of closures rather than a
/// protocol with `associatedtype` to avoid existential / `Self`-requirement
/// friction at SDK construction sites and to keep factory methods composable.
struct QueueEndpoint<Record> {
    // MARK: Storage / threading

    let storageKey: PostHogStorage.StorageKey
    let oldStorageKeys: [PostHogStorage.StorageKey]
    let dispatchQueueLabel: String

    // MARK: Per-config runtime knobs

    /// Reads the initial cap from `PostHogConfig`. Events: `maxBatchSize`.
    /// Logs: `logs.maxBatchSize`.
    let initialCap: (PostHogConfig) -> Int
    /// Reads the initial flush threshold. Events: `flushAt`. Logs: same as cap
    /// since the logs queue uses the cap as its single threshold.
    let initialFlushAt: (PostHogConfig) -> Int
    /// FIFO eviction limit on `add()`. Events: `maxQueueSize`. Logs:
    /// `logs.maxBufferSize`.
    let maxQueueSize: (PostHogConfig) -> Int
    /// Periodic flush interval for the queue's timer.
    let flushIntervalSeconds: (PostHogConfig) -> TimeInterval

    // MARK: Codec

    /// Serialize a record for disk persistence. Returns `nil` if the record
    /// can't be encoded (e.g. NaN attributes); the queue drops it at `add()`.
    let encode: (Record) -> Data?
    /// Deserialize a record from disk. Returns `nil` for unreadable items;
    /// the queue skips them.
    let decode: (Data) -> Record?

    // MARK: Send

    /// Build the wire payload from a list of records and POST it. The queue
    /// passes its `handleResult` continuation as `completion`.
    let send: ([Record], @escaping (PostHogBatchUploadInfo) -> Void) -> Void

    // MARK: Retry policy

    /// Status codes that trigger an exponential-backoff retry of the same
    /// batch. Events: `[429, 500, 502, 503, 504]`. Logs: `[408, 429, 500..599]`.
    let retriableStatusCodes: Set<Int>
    /// Whether 3xx redirects are retriable. Events: yes. Logs: no.
    let redirectIsRetriable: Bool

    // MARK: Cap policy (post-flush)

    /// New cap after a successful flush. Events: stays put. Logs: `min(cap+1, max)`.
    let capAfterSuccess: (_ currentCap: Int, _ maxCap: Int) -> Int
    /// New cap after a poison-drop (size-1 batch + 413). Events: stays at 1.
    /// Logs: resets to `max` since the offending record is gone.
    let capAfterPoisonDrop: (_ currentCap: Int, _ maxCap: Int) -> Int
    /// New cap after a queue-wide drop triggered by `maxRetries` being
    /// exceeded. Events: stays where it is. Logs: resets to `max` because the
    /// queue is now empty and the next batch should start fresh.
    let capAfterDropAll: (_ currentCap: Int, _ maxCap: Int) -> Int
}
