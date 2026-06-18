import Foundation

/// Reserved keys the SDK owns on every step; caller-supplied values for these are stripped.
enum PostHogExceptionStepFields {
    static let message = "$message"
    static let timestamp = "$timestamp"
    /// The event property key under which steps are attached to a `$exception` event.
    static let stepsKey = "$exception_steps"
}

/// Thread-safe FIFO of exception steps bounded by a UTF-8 byte budget. When over budget the oldest
/// steps are evicted (keeping those closest to the exception); a step larger than `maxBytes` is
/// rejected.
///
/// Purely in-memory and crash-agnostic: it is the source for steps attached to non-fatal `$exception`
/// events, and on every change it publishes the current steps via `onStepsChanged`. Fatal-crash
/// durability is handled by a subscriber (the error-tracking integration), not here.
final class PostHogExceptionStepsBuffer {
    private struct Entry {
        let step: [String: Any]
        let bytes: Int
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var totalBytes = 0
    private let maxBytes: Int
    /// Called with the current steps (oldest → newest) on every change. Serialized by `notifyLock`
    /// (not `lock`) so the callback's work doesn't block readers and snapshots publish in change order;
    /// the callback must not call back into `add`/`clear`.
    private let onStepsChanged: (([[String: Any]]) -> Void)?
    /// Serializes snapshot-capture + callback so published steps stay ordered (incl. the `clear()` at
    /// close), while keeping the callback off `lock` so `getAttachable` isn't blocked behind it.
    private let notifyLock = NSLock()
    /// Set by `clear()` at end of run; further adds become no-ops so a record racing `close()` can't
    /// re-publish steps after teardown.
    private var closed = false

    init(maxBytes: Int, onStepsChanged: (([[String: Any]]) -> Void)? = nil) {
        self.maxBytes = max(0, maxBytes)
        self.onStepsChanged = onStepsChanged
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

        // Serialize once to measure the byte cost for the budget.
        guard let data = try? JSONSerialization.data(withJSONObject: normalized) else {
            return false
        }
        let bytes = data.count

        guard bytes <= maxBytes else {
            return false
        }

        return notifyLock.withLock {
            let snapshot: [[String: Any]]? = lock.withLock {
                guard !closed else { return nil }
                entries.append(Entry(step: normalized, bytes: bytes))
                totalBytes += bytes
                trimToMaxBytesLocked()
                return entries.map(\.step)
            }
            guard let snapshot else { return false }
            onStepsChanged?(snapshot)
            return true
        }
    }

    /// The buffered steps, ordered oldest → newest (for non-fatal `$exception` attach).
    func getAttachable() -> [[String: Any]] {
        lock.withLock { entries.map(\.step) }
    }

    var isEmpty: Bool {
        lock.withLock { entries.isEmpty }
    }

    /// Empty the buffer and close it to further recording (called at end of run; not reused after).
    func clear() {
        notifyLock.withLock {
            lock.withLock {
                closed = true
                entries.removeAll()
                totalBytes = 0
            }
            onStepsChanged?([])
        }
    }

    /// Evict oldest steps until within budget. Callers must hold `lock`.
    private func trimToMaxBytesLocked() {
        while totalBytes > maxBytes, !entries.isEmpty {
            totalBytes -= entries.removeFirst().bytes
        }
    }
}

/// Composes the crash reporter's `customData` as the cached context plus the current exception steps
/// (`{ …context, $exception_steps: [...] }`) and writes it synchronously, so a step recorded right
/// before a fatal crash is durable before the recording call returns.
///
/// Owned by the error-tracking integration, which feeds it context and step updates. The vendored
/// `customData` setter is not safe for concurrent writers, so writes are serialized by a process-
/// global lock (covers the brief window where an old and new instance coexist during opt-out/opt-in).
final class PostHogCrashCustomDataWriter {
    private static let writeLock = NSLock()

    private let lock = NSLock()
    private let write: (Data) -> Void
    private var context: [String: Any] = [:]
    private var steps: [[String: Any]] = []

    init(write: @escaping (Data) -> Void) {
        self.write = write
    }

    /// Update the cached crash context and rewrite `customData` (steps unchanged).
    func setContext(_ context: [String: Any]) {
        lock.withLock {
            self.context = context
            writeLocked()
        }
    }

    /// Update the cached steps and rewrite `customData` (context unchanged).
    func setSteps(_ steps: [[String: Any]]) {
        lock.withLock {
            self.steps = steps
            writeLocked()
        }
    }

    /// Rewrite `customData` = context + steps. Callers must hold `lock`.
    private func writeLocked() {
        var payload = context
        payload[PostHogExceptionStepFields.stepsKey] = steps
        guard let blob = try? JSONSerialization.data(withJSONObject: payload) else {
            hedgeLog("Failed to serialize exception steps customData")
            return
        }
        Self.writeLock.withLock { write(blob) }
    }
}
