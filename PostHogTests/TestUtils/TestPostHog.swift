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

func waitDecideRequest(_ server: MockPostHogServer) {
    let result = XCTWaiter.wait(for: [server.decideExpectation!], timeout: 15)

    if result != XCTWaiter.Result.completed {
        XCTFail("The expected requests never arrived")
    }
}

func getDecideRequest(_ server: MockPostHogServer) -> [[String: Any]] {
    waitDecideRequest(server)

    var requests: [[String: Any]] = []
    for request in server.decideRequests.reversed() {
        let item = server.parseRequest(request, gzip: false)
        requests.append(item!)
    }

    return requests
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

final class BundleLocator {}

final class MockDate {
    var date = Date()
}
