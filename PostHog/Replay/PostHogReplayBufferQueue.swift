import Foundation

/// A disk-based buffer queue for session replay snapshots.
/// Uses UUID v7 filenames (consistent with `PostHogFileBackedQueue`) so items
/// can be migrated directly to the replay queue. Timestamps for duration
/// calculations are extracted from the UUID v7 embedded millisecond epoch.
class PostHogReplayBufferQueue {
    private let queue: URL
    private var items = [String]()
    private let itemsLock = NSLock()

    var depth: Int {
        itemsLock.withLock { items.count }
    }

    /// Returns the time span between the oldest and newest buffered items,
    /// based on the UUID v7 embedded timestamps.
    var bufferDuration: TimeInterval? {
        itemsLock.withLock {
            guard let oldest = items.first,
                  let newest = items.last,
                  let oldestTs = Self.timestampFromUUIDv7(oldest),
                  let newestTs = Self.timestampFromUUIDv7(newest)
            else {
                return nil
            }
            return max(newestTs - oldestTs, 0)
        }
    }

    /// Returns the timestamp of the oldest buffered item, if any.
    var oldestTimestamp: TimeInterval? {
        itemsLock.withLock {
            guard let oldest = items.first else { return nil }
            return Self.timestampFromUUIDv7(oldest)
        }
    }

    /// Returns the timestamp of the newest buffered item, if any.
    var newestTimestamp: TimeInterval? {
        itemsLock.withLock {
            guard let newest = items.last else { return nil }
            return Self.timestampFromUUIDv7(newest)
        }
    }

    init(queue: URL) {
        self.queue = queue
        setup()
    }

    private func setup() {
        // Clear any leftover buffer from previous sessions - if they're still here,
        // they didn't meet the minimum duration threshold and should be discarded
        deleteSafely(queue)

        do {
            try FileManager.default.createDirectory(atPath: queue.path, withIntermediateDirectories: true)
        } catch {
            hedgeLog("Error trying to create replay buffer folder \(error)")
        }

        items = []
    }

    func add(_ contents: Data) {
        do {
            let filename = UUID.v7().uuidString
            try contents.write(to: queue.appendingPathComponent(filename))
            itemsLock.withLock { items.append(filename) }
        } catch {
            hedgeLog("Could not write replay buffer file \(error)")
        }
    }

    /// Removes items older than `newestTimestamp - duration`
    /// This will keep ~minimumDuration worth of snapshots in the buffer.
    func pruneOlderThan(duration: TimeInterval) {
        let newestTs: TimeInterval? = itemsLock.withLock {
            guard let newest = items.last else { return nil }
            return Self.timestampFromUUIDv7(newest)
        }
        guard let newestTs else { return }
        let cutoff = newestTs - duration

        // items should be sorted older -> newer already
        itemsLock.withLock {
            while let first = items.first,
                  let ts = Self.timestampFromUUIDv7(first),
                  ts < cutoff
            {
                let removedItem = items.removeFirst()
                deleteSafely(queue.appendingPathComponent(removedItem))
            }
        }
    }

    /// Migrates all buffered items to the target `PostHogFileBackedQueue`.
    /// Moves both the on-disk files and appends filenames to the target's in-memory items list.
    /// After migration, the buffer is empty.
    func migrateAll(to target: PostHogFileBackedQueue) {
        let itemsToMigrate: [String] = itemsLock.withLock {
            let copy = items
            items.removeAll()
            return copy
        }

        let fileManager = FileManager.default
        for item in itemsToMigrate {
            let sourceURL = queue.appendingPathComponent(item)
            let destinationURL = target.queue.appendingPathComponent(item)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: sourceURL)
                } else {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                hedgeLog("Failed to migrate replay buffer item \(item): \(error)")
            }
        }

        // Reload target queue from disk to pick up migrated files (sorted by creation date)
        target.reloadFromDisk()
    }

    /// Removes all buffered items from disk and memory.
    func clear() {
        deleteSafely(queue)
        setup()
    }

    // MARK: - UUID v7 Timestamp Extraction

    /// Extracts the millisecond epoch timestamp from a UUID v7 string.
    /// UUID v7 encodes Unix milliseconds in the first 48 bits (first 12 hex chars).
    /// Returns seconds since epoch as `TimeInterval`, or nil if parsing fails.
    static func timestampFromUUIDv7(_ uuidString: String) -> TimeInterval? {
        // UUID v7 format: XXXXXXXX-XXXX-7XXX-XXXX-XXXXXXXXXXXX
        // First 48 bits (12 hex chars across first two groups) = milliseconds since epoch
        let cleaned = uuidString.replacingOccurrences(of: "-", with: "")
        guard cleaned.count >= 12 else { return nil }
        let hexTimestamp = String(cleaned.prefix(12))
        guard let milliseconds = UInt64(hexTimestamp, radix: 16) else { return nil }
        return TimeInterval(milliseconds) / 1_000.0
    }
}
