//
//  SessionManagerTest.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class SessionManagerTest: QuickSpec {
    override func spec() {
        var sessionManager: PostHogSessionManager!
        var config: PostHogConfig!

        beforeEach {
            config = PostHogConfig(apiKey: "test")
            sessionManager = PostHogSessionManager(config: config)
        }

        it("Generates an anonymousId") {
            let anonymousId = sessionManager.getAnonymousId()
            expect(anonymousId) != nil
            let secondAnonymousId = sessionManager.getAnonymousId()
            expect(secondAnonymousId) == anonymousId
        }

        it("Uses the anonymousId for distinctId if not set") {
            let anonymousId = sessionManager.getAnonymousId()
            let distinctId = sessionManager.getDistinctId()
            expect(distinctId) == anonymousId

            let idToSet = UUID().uuidString
            sessionManager.setDistinctId(idToSet)
            let newAnonymousId = sessionManager.getAnonymousId()
            let newDistinctId = sessionManager.getDistinctId()
            expect(newAnonymousId) == anonymousId
            expect(newAnonymousId) != newDistinctId
            expect(newDistinctId) == idToSet
        }
    }
}
