//
//  TestPostHog.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import PostHog
import XCTest

class TestPostHog {
    var server: MockPostHogServer!
    var posthog: PostHog!

    init() {
        server = MockPostHogServer()
        server.start()
        let config = server.posthogConfig
        posthog = PostHog.with(config)
    }

    func stop() {
        server.stop()
        posthog.reset()
    }

    func getBatchedEvents() -> [PostHogEvent] {
        posthog.flush()
        let result = XCTWaiter.wait(for: [server.expectation(1)], timeout: 2.0)

        if result != XCTWaiter.Result.completed {
            XCTFail("The expected requests never arrived")
        }

        for request in server.requests.reversed() {
            if request.url?.path == "/batch" {
                return server.parsePostHogEvents(request)
            }
        }

        return []
    }
}
