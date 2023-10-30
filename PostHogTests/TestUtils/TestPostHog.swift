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

    func getBatchedEvents() -> [PostHogEvent] {
        let result = XCTWaiter.wait(for: [server.expectation(1)], timeout: 10.0)

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
