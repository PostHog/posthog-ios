import Foundation

/// Reserved keys that the SDK controls on every exception step.
///
/// Values supplied by the caller under these keys are stripped — the SDK sets the canonical
/// `$message` and `$timestamp`.
enum PostHogExceptionStepFields {
    static let message = "$message"
    static let timestamp = "$timestamp"
    /// The event property key under which steps are attached to a `$exception` event.
    static let stepsKey = "$exception_steps"
}

/// Thread-safe FIFO buffer of exception steps bounded by a UTF-8 byte budget, mirrored to disk so
/// steps survive a fatal crash.
///
/// Steps are kept oldest-first; when the cumulative serialized size exceeds `maxBytes` the oldest
/// steps are evicted first (the steps closest in time to the exception are the most diagnostically
/// valuable). A single step larger than `maxBytes` is rejected outright.
///
/// When a `directory` is provided, each step is also written to its own small file (one append per
/// step, so recording stays cheap). On the next launch a pending crash report reads those files via
/// `readPersistedSteps(from:)` and attaches them to the crash `$exception`. The live buffer starts
/// each session empty: constructing it clears the directory, so `readPersistedSteps` must run before
/// the buffer is created.
///
/// All in-memory access is guarded by a lock so the recording path (`addExceptionStep`) and the
/// capture path can run on different threads safely. File writes/deletes happen outside the lock.
final class PostHogExceptionStepsBuffer {
    private struct Entry {
        let step: [String: Any]
        let bytes: Int
        /// Monotonic sequence number identifying this step. Used by `snapshot()`/`removeUpTo(_:)` to
        /// drop exactly the steps that were attached to an exception while preserving any steps added
        /// afterwards.
        let seq: UInt64
        /// Filename of this step's on-disk mirror, or `nil` when the buffer is memory-only.
        let filename: String?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var totalBytes: Int = 0
    private var nextSeq: UInt64 = 0
    private let maxBytes: Int
    /// Directory mirroring the buffer to disk for fatal-crash durability. `nil` = memory-only.
    private let directory: URL?

    init(maxBytes: Int, directory: URL? = nil) {
        self.maxBytes = max(0, maxBytes)
        self.directory = directory
        if let directory {
            // Start fresh; a previous session's steps are read via `readPersistedSteps` before this init.
            deleteSafely(directory)
            createDirectoryAtURLIfNeeded(url: directory)
        }
    }

    /// Add a step to the buffer.
    ///
    /// Validates the reserved fields, serializes the step to measure its UTF-8 byte size, rejects a
    /// single step larger than the budget, mirrors it to disk, then evicts the oldest steps until
    /// within budget.
    ///
    /// - Returns: `true` if the step was buffered, `false` if it was rejected (invalid or oversized).
    @discardableResult
    func add(_ step: [String: Any]) -> Bool {
        // Normalize to the JSON-safe wire form so the stored, measured, and sent step all match.
        guard let normalized = sanitizeDictionary(step) else {
            return false
        }

        guard let message = normalized[PostHogExceptionStepFields.message] as? String, !message.isEmpty else {
            return false
        }
        let timestamp = normalized[PostHogExceptionStepFields.timestamp]
        guard timestamp is String || timestamp is NSNumber else {
            return false
        }

        // Serialize once; `data` is both the byte measure and the persisted bytes.
        guard let data = try? JSONSerialization.data(withJSONObject: normalized) else {
            return false
        }
        let bytes = data.count

        guard bytes <= maxBytes else {
            return false
        }

        let filename = persist(data)

        let evicted: [String] = lock.withLock {
            entries.append(Entry(step: normalized, bytes: bytes, seq: nextSeq, filename: filename))
            nextSeq += 1
            totalBytes += bytes
            return trimToMaxBytes()
        }
        deleteFiles(evicted)
        return true
    }

    /// The buffered steps, ordered oldest → newest.
    func getAttachable() -> [[String: Any]] {
        lock.withLock { entries.map(\.step) }
    }

    /// A snapshot of the buffered steps plus the sequence high-water mark covering them, or `nil`
    /// when the buffer is empty.
    ///
    /// Pair with `removeUpTo(_:)` to drop exactly the snapshotted steps after they have been attached
    /// to an exception, while preserving any steps recorded after the snapshot was taken.
    func snapshot() -> (steps: [[String: Any]], upTo: UInt64)? {
        lock.withLock {
            guard let last = entries.last else { return nil }
            return (entries.map(\.step), last.seq)
        }
    }

    /// Remove every entry whose sequence number is `<= upTo` (the steps captured by a prior
    /// `snapshot()`), leaving steps added afterwards intact and releasing their byte budget.
    func removeUpTo(_ upTo: UInt64) {
        let removed = lock.withLock { removeEntriesLocked { $0.seq <= upTo } }
        deleteFiles(removed)
    }

    var isEmpty: Bool {
        lock.withLock { entries.isEmpty }
    }

    /// Empty the buffer, deleting the on-disk mirror.
    func clear() {
        let removed = lock.withLock { removeEntriesLocked { _ in true } }
        deleteFiles(removed)
    }

    /// Remove entries matching `predicate`, decrementing the byte total and collecting their
    /// filenames for deletion after the lock is released.
    /// - Important: callers must hold `lock`.
    private func removeEntriesLocked(where predicate: (Entry) -> Bool) -> [String] {
        var files: [String] = []
        entries.removeAll { entry in
            guard predicate(entry) else { return false }
            totalBytes -= entry.bytes
            if let filename = entry.filename { files.append(filename) }
            return true
        }
        return files
    }

    /// Evict the oldest steps until the running total is within budget.
    ///
    /// - Returns: the filenames of evicted steps, to be deleted after the lock is released.
    /// - Important: callers must hold `lock`.
    private func trimToMaxBytes() -> [String] {
        var evicted: [String] = []
        while totalBytes > maxBytes, !entries.isEmpty {
            let removed = entries.removeFirst()
            totalBytes -= removed.bytes
            if let filename = removed.filename { evicted.append(filename) }
        }
        return evicted
    }

    private func persist(_ data: Data) -> String? {
        guard let directory else { return nil }
        let filename = UUID.v7().uuidString
        do {
            try data.write(to: directory.appendingPathComponent(filename))
            return filename
        } catch {
            hedgeLog("Failed to persist exception step: \(error)")
            return nil
        }
    }

    private func deleteFiles(_ filenames: [String]) {
        guard let directory, !filenames.isEmpty else { return }
        for filename in filenames {
            deleteSafely(directory.appendingPathComponent(filename))
        }
    }

    /// Read steps persisted by a previous session (oldest → newest), for attaching to a crash
    /// `$exception` reported on the next launch. Does not mutate the directory.
    static func readPersistedSteps(from directory: URL) -> [[String: Any]] {
        guard directoryExists(directory) else { return [] }

        let urls: [URL]
        do {
            // Read each file's creation date once, then sort.
            urls = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
                .map { (url: $0, date: (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
                .sorted { $0.date < $1.date }
                .map(\.url)
        } catch {
            hedgeLog("Failed to read persisted exception steps: \(error)")
            return []
        }

        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return fromJSONData(data)
        }
    }
}
