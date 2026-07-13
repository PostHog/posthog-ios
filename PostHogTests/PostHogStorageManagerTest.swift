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
        let theConfig = config ?? PostHogConfig(projectToken: "test_project_token")
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
            let config = PostHogConfig(projectToken: "test_project_token")
            let fixedUuid = UUID.v7()
            config.getAnonymousId = { _ in fixedUuid }
            let sut = self.getSut(config)
            let anonymousId = sut.getAnonymousId()
            expect(anonymousId) == fixedUuid.uuidString

            sut.reset(true)
        }

        it("Seeds the anonymous ID from bootstrap.distinctId on fresh install") {
            let config = PostHogConfig(projectToken: "test_project_token")
            config.bootstrap = PostHogBootstrap(anonymousId: "A-bootstrap-id-123")
            let sut = self.getSut(config)

            let anonymousId = sut.getAnonymousId()
            expect(anonymousId) == "A-bootstrap-id-123"

            // Subsequent calls return the same persisted value.
            expect(sut.getAnonymousId()) == "A-bootstrap-id-123"
            // Not flagged as identified — anonymous-only seed.
            expect(sut.isIdentified()) == false

            sut.reset(true)
        }

        it("Ignores empty bootstrap.distinctId and falls back to UUID") {
            let config = PostHogConfig(projectToken: "test_project_token")
            config.bootstrap = PostHogBootstrap(anonymousId: "")
            let sut = self.getSut(config)

            let anonymousId = sut.getAnonymousId()
            expect(anonymousId.isEmpty) == false
            // Should be a UUID, not an empty string.
            expect(UUID(uuidString: anonymousId)) != nil

            sut.reset(true)
        }

        it("Seeds both anonymous and distinct IDs when bootstrap.isIdentifiedId is true") {
            let config = PostHogConfig(projectToken: "test_project_token")
            config.bootstrap = PostHogBootstrap(distinctId: "user-42", isIdentifiedId: true)
            let sut = self.getSut(config)

            expect(sut.getAnonymousId()) == "user-42"
            expect(sut.getDistinctId()) == "user-42"
            expect(sut.isIdentified()) == true

            sut.reset(true)
        }

        it("Treats a distinctId bootstrap as identified by default") {
            let config = PostHogConfig(projectToken: "test_project_token")
            config.bootstrap = PostHogBootstrap(distinctId: "user-99")
            let sut = self.getSut(config)

            expect(sut.getDistinctId()) == "user-99"
            expect(sut.isIdentified()) == true

            sut.reset(true)
        }

        it("Does not re-apply bootstrap once an anonymous ID is persisted") {
            let firstConfig = PostHogConfig(projectToken: "test_project_token")
            firstConfig.bootstrap = PostHogBootstrap(anonymousId: "A-original")
            let firstSut = self.getSut(firstConfig)
            _ = firstSut.getAnonymousId()

            // Simulate a second SDK init in the same install: storage already has
            // the original anonymous ID. The new config supplies a different
            // bootstrap value, which must NOT override the persisted one.
            let secondConfig = PostHogConfig(projectToken: "test_project_token")
            secondConfig.bootstrap = PostHogBootstrap(anonymousId: "A-different")
            let secondSut = PostHogStorageManager(secondConfig)

            expect(secondSut.getAnonymousId()) == "A-original"

            firstSut.reset(true)
        }

        it("Does not re-apply bootstrap after the user has been identified") {
            let firstConfig = PostHogConfig(projectToken: "test_project_token")
            let firstSut = self.getSut(firstConfig)
            firstSut.setIdentified(true)
            firstSut.setDistinctId("identified-user")
            let originalAnon = firstSut.getAnonymousId()

            // A subsequent SDK init that supplies a bootstrap must not re-seed
            // either the anonymous ID or the distinct ID — that would silently
            // re-link traffic across the prior anon→identified merge.
            let secondConfig = PostHogConfig(projectToken: "test_project_token")
            secondConfig.bootstrap = PostHogBootstrap(distinctId: "A-new", isIdentifiedId: true)
            let secondSut = PostHogStorageManager(secondConfig)

            expect(secondSut.getAnonymousId()) == originalAnon
            expect(secondSut.getDistinctId()) == "identified-user"

            firstSut.reset(true)
        }

        it("Uses the correct fallback value for isIdentified") {
            let anonymousIdToSet = UUID.v7()
            let distinctIdToSet = UUID.v7().uuidString

            let config = PostHogConfig(projectToken: "test_project_token")
            config.getAnonymousId = { _ in anonymousIdToSet }

            let sut = self.getSut(config)
            sut.setDistinctId(distinctIdToSet)

            // Don't call setIdentified(true), isIdentified should be derived from different anon and distinct ids
            expect(sut.isIdentified()) == true
        }
    }
}
