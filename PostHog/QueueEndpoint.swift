//
//  QueueEndpoint.swift
//  PostHog
//

import Foundation

/// Per-wire spec consumed by the generic `PostHogQueue<Record>`.
///
/// Encapsulates everything that differs between the events `/batch`, replay
/// `/snapshot`, and logs `/i/v1/logs` endpoints — disk codec, payload assembly,
/// retriable status set — so the queue itself stays record-type-agnostic.
/// Implemented as a struct of closures rather than a protocol with
/// `associatedtype` to avoid existential / `Self`-requirement friction at SDK
/// construction sites and to keep factory methods composable.
///
/// Adaptive batch-cap policy is uniform across all three endpoints (halve on
/// 413, stay put otherwise), so `PostHogQueue.handleResult` hardcodes it
/// rather than parameterising.
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

    // MARK: Rate cap

    /// Records accepted per `rateCapWindowSeconds` before `add(_:)` starts
    /// dropping. Return `0` to disable the cap entirely; events and replay
    /// disable it, logs reads `config.logs.rateCapMaxLogs`.
    let rateCapMax: (PostHogConfig) -> Int
    /// Tumbling-window length used by the rate cap. Ignored when
    /// `rateCapMax` is `0`.
    let rateCapWindowSeconds: (PostHogConfig) -> TimeInterval

    // MARK: Codec

    /// Serialize a record for disk persistence. Returns `nil` if the record
    /// can't be encoded (e.g. NaN attributes); the queue drops it at `add()`.
    let encode: (Record) -> Data?
    /// Deserialize a record from disk. Returns `nil` for unreadable items;
    /// the queue skips them.
    let decode: (Data) -> Record?
    /// Short label for this record used in queue debug logs. Events return
    /// the event name; snapshots / logs return a generic label.
    let describe: (Record) -> String

    // MARK: Send

    /// Build the wire payload from a list of records and POST it. The queue
    /// passes its `handleResult` continuation as `completion`.
    let send: ([Record], @escaping (PostHogUploadInfo) -> Void) -> Void

    // MARK: Retry policy

    /// Returns `true` if the given HTTP status code should trigger an
    /// exponential-backoff retry of the same batch. Each endpoint owns its
    /// retry policy — the queue handles `-1` (network error) separately,
    /// since that case is universal.
    let isRetriableStatusCode: (Int) -> Bool
}
