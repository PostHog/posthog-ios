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
    var posthog: PostHogSDK!

    init(preloadFeatureFlags: Bool = false) {
        server = MockPostHogServer()
        server.start()
        let config = server.getPosthogConfig(preloadFeatureFlags: preloadFeatureFlags)
        posthog = PostHogSDK.with(config)
    }

    func stop() {
        server.stop()
    }

    public func getBatchedEvents() -> [PostHogEvent] {
        PostHogTests.getBatchedEvents(server)
    }
}

func getBatchedEvents(_ server: MockPostHogServer) -> [PostHogEvent] {
    let result = XCTWaiter.wait(for: [server.expectation!], timeout: 10.0)

    if result != XCTWaiter.Result.completed {
        XCTFail("The expected requests never arrived")
    }

    var events: [PostHogEvent] = []
    for request in server.requests.reversed() {
        if request.url?.path == "/batch" {
            let items = server.parsePostHogEvents(request)
            events.append(contentsOf: items)
        }
    }

    return events
}
