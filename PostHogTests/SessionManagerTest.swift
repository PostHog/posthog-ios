//
//  SessionManagerTest.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Nimble
@testable import PostHog
import Quick

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

        it("Generates a session id") {
            let sessionId = sessionManager.getSessionId()
            expect(sessionId).toNot(beNil())

            let secondSessionId = sessionManager.getSessionId()
            expect(secondSessionId) == sessionId
        }

        it("Generates a new session id if last timestamp is older") {
            let sessionId = sessionManager.getSessionId()
            expect(sessionId).toNot(beNil())

            changeSessionLastTimestamp(timeToAdd: TimeInterval(0 - sessionManager.sessionChangeThreshold + 100))
            let sameSessionId = sessionManager.getSessionId()
            expect(sameSessionId) == sessionId

            changeSessionLastTimestamp(timeToAdd: TimeInterval(0 - sessionManager.sessionChangeThreshold - 100))
            let newSessionId = sessionManager.getSessionId()
            expect(newSessionId) != sessionId
        }
    }
}
