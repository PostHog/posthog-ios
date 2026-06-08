//
//  TestPostHog.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick
import XCTest

final class TestPollingConfiguration: QuickConfiguration {
    override class func configure(_ configuration: QCKConfiguration) {
        // Shared CI runners run several times slower than local (one job was ~6x), so Nimble's
        // default 1s poll timeout makes async assertions flake when background work is starved.
        // Raise the ceiling generously — toEventually still returns as soon as it passes.
        PollingDefaults.timeout = .seconds(30)
        configuration.beforeEach {
            // Some suites mock the global `now` clock and don't restore it; a leaked fixed clock
            // makes the timestamp-keyed queue collide events (lost batches). Reset before each test.
            now = { Date() }
            // storage.reset() deliberately keeps the on-disk event queue, so a prior test's unsent
            // event can leak into the next test's batch and inflate counts. Wipe persisted state so
            // every Quick test starts from a clean slate.
            deleteSafely(applicationSupportDirectoryURL())
        }
    }
}

// Shared CI runners run several times slower than local, so the request-arrival waits below need the
// same generous ceiling we give Nimble's PollingDefaults above — otherwise a starved background flush
// makes "the expected requests never arrived" flake. The fast path still returns as soon as the
// request lands; the ceiling only matters when the runner is contended.
let testRequestTimeout: TimeInterval = 30.0

func getBatchedEvents(_ server: MockPostHogServer, timeout: TimeInterval = testRequestTimeout, failIfNotCompleted: Bool = true) -> [PostHogEvent] {
    let result = XCTWaiter.wait(for: [server.batchExpectation!], timeout: timeout)

    if result != XCTWaiter.Result.completed, failIfNotCompleted {
        XCTFail("The expected requests never arrived")
    }

    var events: [PostHogEvent] = []
    for request in server.batchRequests.reversed() {
        let items = server.parsePostHogEvents(request)
        events.append(contentsOf: items)
    }

    return events
}

func waitFlagsRequest(_ server: MockPostHogServer) {
    let result = XCTWaiter.wait(for: [server.flagsExpectation!], timeout: testRequestTimeout)

    if result != XCTWaiter.Result.completed {
        XCTFail("The expected requests never arrived")
    }
}

// lastRequestId can already be non-nil (restored from disk or an earlier load), so waiting on it
// would pass before the fresh response lands. didReceiveFeatureFlags fires only after a /flags
// response is stored; observe it from before the request so the notification can't be missed.
func waitForFeatureFlagsLoaded(_ server: MockPostHogServer, _: PostHogSDK) {
    let flagsLoaded = XCTNSNotificationExpectation(name: PostHogSDK.didReceiveFeatureFlags)
    waitFlagsRequest(server)
    if XCTWaiter.wait(for: [flagsLoaded], timeout: testRequestTimeout) != .completed {
        XCTFail("Feature flags were not loaded in time")
    }
}

func waitForSnapshotRequest(_ server: MockPostHogServer) async throws {
    guard let expectation = server.snapshotExpectation else {
        throw TestError("Server is not properly configured with a snapshot expectation.")
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let result = XCTWaiter.wait(for: [expectation], timeout: testRequestTimeout)

        switch result {
        case .completed:
            continuation.resume()
        case .timedOut:
            continuation.resume(throwing: TestError("Timeout occurred while waiting for snapshot request."))
        default:
            continuation.resume(throwing: TestError("Unexpected XCTWaiter result: \(result)."))
        }
    }
}

func getFlagsRequest(_ server: MockPostHogServer) -> [[String: Any]] {
    waitFlagsRequest(server)

    var requests: [[String: Any]] = []
    for request in server.flagsRequests.reversed() {
        let item = server.parseRequest(request, gzip: false)
        requests.append(item!)
    }

    return requests
}

func getServerEvents(_ server: MockPostHogServer) async throws -> [PostHogEvent] {
    guard let expectation = server.batchExpectation else {
        throw TestError("Server is not properly configured with a batch expectation.")
    }

    return try await withCheckedThrowingContinuation { continuation in
        let result = XCTWaiter.wait(for: [expectation], timeout: testRequestTimeout)

        switch result {
        case .completed:
            continuation.resume(returning: server.batchRequests.flatMap { server.parsePostHogEvents($0) })
        case .timedOut:
            continuation.resume(throwing: TestError("Timeout occurred while waiting for server events."))
        default:
            continuation.resume(throwing: TestError("Unexpected XCTWaiter result: \(result)."))
        }
    }
}

final class MockDate {
    var date = Date()
}

/// Event-driven replacement for the `while !flag, Date() < timeout {}` busy-waits that used to peg a
/// thread for up to N seconds — and, on the cooperative pool, could starve the very callback they were
/// waiting on. Create it with the number of callbacks to await, call `signal()` from each, then
/// `await wait()`. It resumes the instant the last signal lands; the timeout is only a safety net so a
/// regression fails fast instead of hanging the whole run.
final class AsyncLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    init(count: Int = 1) {
        remaining = count
    }

    /// Records one awaited callback; opens the latch once all of them have arrived. Thread-safe and
    /// idempotent — extra calls after the latch opens are ignored.
    func signal() {
        lock.lock()
        if opened {
            lock.unlock()
            return
        }
        remaining -= 1
        let shouldOpen = remaining <= 0
        let waiter = shouldOpen ? takeWaiterLocked() : nil
        lock.unlock()
        waiter?.resume()
    }

    /// Suspends until every `signal()` has landed or `timeout` seconds elapse. `settle` lets trailing
    /// async work finish before returning, preserving the small post-callback delays a few of the old
    /// waits relied on.
    func wait(timeout: TimeInterval = 10, settle: TimeInterval = 0) async {
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self.forceOpen()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            let alreadyOpen = opened
            if !alreadyOpen {
                self.continuation = continuation
            }
            lock.unlock()
            if alreadyOpen {
                continuation.resume()
            }
        }
        timeoutTask.cancel()
        if settle > 0 {
            try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
        }
    }

    private func forceOpen() {
        lock.lock()
        let waiter = opened ? nil : takeWaiterLocked()
        lock.unlock()
        waiter?.resume()
    }

    /// Marks the latch open and hands back the pending waiter (if any) to resume outside the lock.
    /// Must be called with `lock` held.
    private func takeWaiterLocked() -> CheckedContinuation<Void, Never>? {
        opened = true
        let waiter = continuation
        continuation = nil
        return waiter
    }
}

extension Bundle {
    static var test: Bundle {
        #if SWIFT_PACKAGE
            return .module
        #else
            return .init(for: BundleLocator.self)
        #endif
    }
}

let testBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.posthog.test"

let testAppGroupIdentifier = "group.com.posthog.test"

final class BundleLocator {}

let testProjectToken = "test_project_token"
