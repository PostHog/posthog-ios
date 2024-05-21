//
//  PostHogSessionManagerTest.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogSessionManagerTest: QuickSpec {
    func getSut() -> PostHogSessionManager {
        let config = PostHogConfig(apiKey: "123")
        return PostHogSessionManager(config)
    }

    override func spec() {
        it("Generates an anonymousId") {
            let sut = self.getSut()

            let anonymousId = sut.getAnonymousId()
            expect(anonymousId) != nil
            let secondAnonymousId = sut.getAnonymousId()
            expect(secondAnonymousId) == anonymousId

            sut.reset()
        }

        it("Uses the anonymousId for distinctId if not set") {
            let sut = self.getSut()

            let anonymousId = sut.getAnonymousId()
            let distinctId = sut.getDistinctId()
            expect(distinctId) == anonymousId

            let idToSet = UUID().uuidString
            sut.setDistinctId(idToSet)
            let newAnonymousId = sut.getAnonymousId()
            let newDistinctId = sut.getDistinctId()
            expect(newAnonymousId) == anonymousId
            expect(newAnonymousId) != newDistinctId
            expect(newDistinctId) == idToSet

            sut.reset()
        }

        it("Can can accept id customization via config") {
            let config = PostHogConfig(apiKey: "123")
            let fixedUuid = UUID()
            config.getAnonymousId = { _ in fixedUuid }
            let sut = PostHogSessionManager(config)
            let anonymousId = sut.getAnonymousId()
            expect(anonymousId) == fixedUuid.uuidString

            sut.reset()
        }
    }
}
