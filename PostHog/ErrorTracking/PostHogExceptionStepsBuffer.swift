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

/// Thread-safe FIFO buffer of exception steps bounded by a UTF-8 byte budget.
///
/// Mirrors the browser SDK's `ExceptionStepsBuffer` (`@posthog/core`). Steps are kept oldest-first;
/// when the cumulative serialized size exceeds `maxBytes` the oldest steps are evicted first (the
/// steps closest in time to the exception are the most diagnostically valuable). A single step
/// larger than `maxBytes` is rejected outright.
///
/// All access is guarded by a lock so the recording path (`addExceptionStep`) and the capture /
/// crash-context paths can run on different threads safely.
final class PostHogExceptionStepsBuffer {
    private struct Entry {
        let step: [String: Any]
        let bytes: Int
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var totalBytes: Int = 0
    private let maxBytes: Int

    init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    /// Add a step to the buffer.
    ///
    /// Validates the reserved fields, serializes the step to measure its UTF-8 byte size, rejects a
    /// single step larger than the budget, then evicts the oldest steps until within budget.
    ///
    /// - Returns: `true` if the step was buffered, `false` if it was rejected (invalid or oversized).
    @discardableResult
    func add(_ step: [String: Any]) -> Bool {
        // Normalize to the JSON-safe wire form first, using the same `[String: Any]` normalization
        // applied to event properties on capture (Date -> ISO-8601, URL -> string, non-serializable
        // values dropped). This keeps the stored step, its measured byte size, and the attached step
        // all identical to what is actually sent.
        guard let normalized = sanitizeDictionary(step) else {
            return false
        }

        // Validate reserved fields: $message must be a non-empty string, $timestamp a string or number.
        guard let message = normalized[PostHogExceptionStepFields.message] as? String, !message.isEmpty else {
            return false
        }
        let timestamp = normalized[PostHogExceptionStepFields.timestamp]
        guard timestamp is String || timestamp is NSNumber else {
            return false
        }

        // Measure the serialized UTF-8 byte size of the normalized step. `normalized` is already
        // JSON-safe, so serialize it directly rather than re-running `sanitizeDictionary` via `toJSONData`.
        guard let data = try? JSONSerialization.data(withJSONObject: normalized) else {
            return false
        }
        let bytes = data.count

        return lock.withLock {
            // A single step larger than the whole budget is rejected outright.
            guard bytes <= maxBytes else {
                return false
            }
            entries.append(Entry(step: normalized, bytes: bytes))
            totalBytes += bytes
            trimToMaxBytes()
            return true
        }
    }

    /// The buffered steps, ordered oldest → newest.
    func getAttachable() -> [[String: Any]] {
        lock.withLock { entries.map(\.step) }
    }

    var isEmpty: Bool {
        lock.withLock { entries.isEmpty }
    }

    /// Empty the buffer and reset the running byte total.
    func clear() {
        lock.withLock {
            entries.removeAll()
            totalBytes = 0
        }
    }

    /// Evict the oldest steps until the running total is within budget.
    ///
    /// - Important: callers must hold `lock`.
    private func trimToMaxBytes() {
        while totalBytes > maxBytes, !entries.isEmpty {
            let removed = entries.removeFirst()
            totalBytes -= removed.bytes
        }
    }
}
