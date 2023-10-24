//
//  SessionManagerTest.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Nimble
@testable import PostHog
import Quick
import Foundation

class SessionManagerTest: QuickSpec {
    override func spec() {
        var sessionManager: PostHogSessionManager!
        var config: PostHogConfig!

        func changeSessionLastTimestamp(timeToAdd: TimeInterval) {
            // Forcefully set the timestamp to the past
            let olderSessionTimestamp = Date().addingTimeInterval(timeToAdd).timeIntervalSince1970
            PostHogStorage(config).setNumber(forKey: .sessionlastTimestamp, contents: Double(olderSessionTimestamp))
        }

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
