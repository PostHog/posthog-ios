import Foundation

/// Reserved keys the SDK owns on every step; caller-supplied values for these are stripped.
enum PostHogExceptionStepFields {
    static let message = "$message"
    static let timestamp = "$timestamp"
    /// The event property key under which steps are attached to a `$exception` event.
    static let stepsKey = "$exception_steps"
}

/// Thread-safe FIFO buffer of exception steps bounded by a UTF-8 byte budget. When over budget the
/// oldest steps are evicted (keeping those closest to the exception); a step larger than `maxBytes`
/// is rejected.
///
/// With a `directory`, each step is mirrored to its own file so it survives a fatal crash; a pending
/// crash on next launch reads them via `readPersistedSteps(from:)`. Constructing the buffer clears
/// the directory, so `readPersistedSteps` must run before construction.
///
/// File I/O happens outside the lock that guards in-memory access.
final class PostHogExceptionStepsBuffer {
    private struct Entry {
        let step: [String: Any]
        let bytes: Int
        let filename: String?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var totalBytes: Int = 0
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

    /// Add a step. Returns `false` if it is invalid (empty message / bad timestamp) or larger than
    /// the whole budget.
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
            entries.append(Entry(step: normalized, bytes: bytes, filename: filename))
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

    var isEmpty: Bool {
        lock.withLock { entries.isEmpty }
    }

    /// Empty the buffer, deleting the on-disk mirror.
    func clear() {
        let removed: [String] = lock.withLock {
            let files = entries.compactMap(\.filename)
            entries.removeAll()
            totalBytes = 0
            return files
        }
        deleteFiles(removed)
    }

    /// Evict oldest steps until within budget, returning their filenames to delete after unlocking.
    /// Callers must hold `lock`.
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
            // Filenames are UUID-v7 (monotonic, time-ordered), so a lexical sort restores FIFO order.
            urls = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
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
