import Foundation

/// Passive observations, not a replacement for the SDK's queue or retry policy.
final class RequestTracker {
    struct Snapshot {
        let requests: [TrackedRequest]
        let captured: Int
        let sent: Int
        let pending: Int
        let inFlight: Int

        var retries: Int { requests.filter { $0.retryAttempt > 0 }.count }
    }

    private let lock = NSLock()
    private var requests: [TrackedRequest] = []
    private var captured: [String] = []
    private var acknowledged = Set<String>()
    private var sent = Set<String>()
    private var attempts: [String: Int] = [:]
    private var inFlight = 0
    private var unobservedCaptures = 0

    func beginCapture() -> Int {
        lock.lock()
        defer { lock.unlock() }
        unobservedCaptures += 1
        return captured.count
    }

    func finishCapture(after index: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard captured.count > index else { return nil }
        unobservedCaptures -= 1
        return captured[index]
    }

    func observeCapture(uuid: String) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(uuid.lowercased())
    }

    func beginRequest() {
        lock.lock()
        defer { lock.unlock() }
        inFlight += 1
    }

    func endRequest() {
        lock.lock()
        defer { lock.unlock() }
        inFlight -= 1
    }

    func observeResponse(status: Int, uuids: [String], timestampMs: Int64) {
        lock.lock()
        defer { lock.unlock() }
        let ids = uuids.map { $0.lowercased() }
        let attempt = ids.compactMap { attempts[$0] }.max() ?? 0
        for id in ids {
            attempts[id, default: 0] += 1
        }
        requests.append(TrackedRequest(
            timestampMs: timestampMs, statusCode: status, retryAttempt: attempt,
            eventCount: ids.count, uuidList: ids
        ))
        if (200 ... 299).contains(status) {
            sent.formUnion(ids)
            acknowledged.formUnion(ids)
        } else if [400, 401, 403, 404, 422].contains(status) || (status == 413 && ids.count == 1) {
            // Known terminal responses for /batch. A multi-event 413 can split/retry.
            acknowledged.formUnion(ids)
        }
        // A retry budget alone cannot establish that the SDK actually dropped a record.
        // Keep transient/network failures outstanding, including after apparent exhaustion.
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            requests: requests, captured: captured.count, sent: sent.count,
            pending: Set(captured).subtracting(acknowledged).count + unobservedCaptures,
            inFlight: inFlight
        )
    }

    /// Waits for observed acknowledgments without initiating any additional SDK flushes.
    func waitForAcknowledgments(timeout: TimeInterval = 25) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let observation = snapshot()
            if observation.pending == 0, observation.inFlight == 0 { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}
