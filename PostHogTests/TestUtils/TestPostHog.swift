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
