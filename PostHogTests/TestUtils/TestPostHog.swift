//
//  TestPostHog.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import PostHog
import XCTest

func getBatchedEvents(_ server: MockPostHogServer) -> [PostHogEvent] {
    let result = XCTWaiter.wait(for: [server.batchExpectation!], timeout: 15.0)

    if result != XCTWaiter.Result.completed {
        XCTFail("The expected requests never arrived")
    }

    var events: [PostHogEvent] = []
    for request in server.batchRequests.reversed() {
        if request.url?.path == "/batch" {
            let items = server.parsePostHogEvents(request)
            events.append(contentsOf: items)
        }
    }

    return events
}

func waitDecideRequest(_ server: MockPostHogServer) {
    let result = XCTWaiter.wait(for: [server.decideExpectation!], timeout: 15)

    if result != XCTWaiter.Result.completed {
        XCTFail("The expected requests never arrived")
    }
}
