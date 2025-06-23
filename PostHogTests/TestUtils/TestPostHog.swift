//
//  TestPostHog.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import PostHog
import XCTest

func getBatchedEvents(_ server: MockPostHogServer, timeout: TimeInterval = 15.0, failIfNotCompleted: Bool = true) -> [PostHogEvent] {
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
    let result = XCTWaiter.wait(for: [server.flagsExpectation!], timeout: 15)

    if result != XCTWaiter.Result.completed {
        XCTFail("The expected requests never arrived")
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
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)

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

let testAPIKey = "test_api_key"
