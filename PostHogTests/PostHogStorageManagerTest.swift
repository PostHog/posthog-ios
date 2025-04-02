//
//  PostHogStorageManagerTest.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogStorageManagerTest: QuickSpec {
    func getSut(_ config: PostHogConfig? = nil) -> PostHogStorageManager {
        let theConfig = config ?? PostHogConfig(apiKey: "123")
        let storage = PostHogStorage(theConfig)
        storage.reset()
        return PostHogStorageManager(theConfig)
    }

    override func spec() {
        it("Generates an anonymousId") {
            let sut = self.getSut()

            let anonymousId = sut.getAnonymousId()
            expect(anonymousId) != nil
            let secondAnonymousId = sut.getAnonymousId()
            expect(secondAnonymousId) == anonymousId

            sut.reset(true)
        }

        it("Uses the anonymousId for distinctId if not set") {
            let sut = self.getSut()

            let anonymousId = sut.getAnonymousId()
            let distinctId = sut.getDistinctId()
            expect(distinctId) == anonymousId

            let idToSet = UUID.v7().uuidString
            sut.setDistinctId(idToSet)
            let newAnonymousId = sut.getAnonymousId()
            let newDistinctId = sut.getDistinctId()
            expect(newAnonymousId) == anonymousId
            expect(newAnonymousId) != newDistinctId
            expect(newDistinctId) == idToSet

            sut.reset(true)
        }

        it("Can accept anon id customization via config") {
            let config = PostHogConfig(apiKey: "123")
            let fixedUuid = UUID.v7()
            config.getAnonymousId = { _ in fixedUuid }
            let sut = self.getSut(config)
            let anonymousId = sut.getAnonymousId()
            expect(anonymousId) == fixedUuid.uuidString

            sut.reset(true)
        }

        it("Uses the correct fallback value for isIdentified") {
            let anonymousIdToSet = UUID.v7()
            let distinctIdToSet = UUID.v7().uuidString

            let config = PostHogConfig(apiKey: "123")
            config.getAnonymousId = { _ in anonymousIdToSet }

            let sut = self.getSut(config)
            sut.setDistinctId(distinctIdToSet)

            // Don't call setIdentified(true), isIdentified should be derived from different anon and distinct ids
            expect(sut.isIdentified()) == true
        }
    }
}
