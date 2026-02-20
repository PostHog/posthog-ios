//
//  PostHogStorageManagerTest.swift
//  PostHogTests
//
//  Created by Ben White on 22.03.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogStorageManager Tests")
struct PostHogStorageManagerTest {
    func getSut(_ config: PostHogConfig? = nil) -> PostHogStorageManager {
        let theConfig = config ?? PostHogConfig(apiKey: uniqueApiKey())
        let storage = PostHogStorage(theConfig)
        storage.reset()
        return PostHogStorageManager(theConfig)
    }

    @Test("Generates an anonymousId")
    func generatesAnAnonymousId() {
        let sut = getSut()

        let anonymousId = sut.getAnonymousId()
        #expect(!anonymousId.isEmpty)
        let secondAnonymousId = sut.getAnonymousId()
        #expect(secondAnonymousId == anonymousId)

        sut.reset(true)
    }

    @Test("Uses the anonymousId for distinctId if not set")
    func usesAnonymousIdForDistinctIdIfNotSet() {
        let sut = getSut()

        let anonymousId = sut.getAnonymousId()
        let distinctId = sut.getDistinctId()
        #expect(distinctId == anonymousId)

        let idToSet = UUID.v7().uuidString
        sut.setDistinctId(idToSet)
        let newAnonymousId = sut.getAnonymousId()
        let newDistinctId = sut.getDistinctId()
        #expect(newAnonymousId == anonymousId)
        #expect(newAnonymousId != newDistinctId)
        #expect(newDistinctId == idToSet)

        sut.reset(true)
    }

    @Test("Can accept anon id customization via config")
    func canAcceptAnonIdCustomizationViaConfig() {
        let config = PostHogConfig(apiKey: uniqueApiKey())
        let fixedUuid = UUID.v7()
        config.getAnonymousId = { _ in fixedUuid }
        let sut = getSut(config)
        let anonymousId = sut.getAnonymousId()
        #expect(anonymousId == fixedUuid.uuidString)

        sut.reset(true)
    }

    @Test("Uses the correct fallback value for isIdentified")
    func usesCorrectFallbackValueForIsIdentified() {
        let anonymousIdToSet = UUID.v7()
        let distinctIdToSet = UUID.v7().uuidString

        let config = PostHogConfig(apiKey: uniqueApiKey())
        config.getAnonymousId = { _ in anonymousIdToSet }

        let sut = getSut(config)
        sut.setDistinctId(distinctIdToSet)

        // Don't call setIdentified(true), isIdentified should be derived from different anon and distinct ids
        #expect(sut.isIdentified() == true)
    }
}
