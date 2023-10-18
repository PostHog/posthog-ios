//
//  FeatureFlagsTest.swift
//  PostHogTests
//
//  Created by Ben White on 08.02.23.
//

import Nimble
import Quick

@testable import PostHog

class FeatureFlagTests: QuickSpec {
    override func spec() {
        var harness: TestPostHog!
        var posthog: PostHogSDK!

        beforeEach {
            harness = TestPostHog()
            posthog = harness.posthog

            let expectation = self.expectation(description: "Waits for flags")
            posthog.reloadFeatureFlags { _, _ in
                expectation.fulfill()
            }

            await self.fulfillment(of: [expectation])
        }
        afterEach {
            harness.stop()
        }

        it("responds false for missing flag enabled") {
            let isEnabled = posthog.isFeatureEnabled("missing")
            expect(isEnabled) == false
        }

        it("responds nil for missing flag get") {
            let isEnabled = posthog.getFeatureFlag("missing")
            expect(isEnabled) == nil
        }

        it("checks flag is enabled") {
            let isEnabled = posthog.isFeatureEnabled("bool-value")
            expect(isEnabled) == true
        }

        it("checks multivariate flag is enabled") {
            guard let flagValue = posthog.getFeatureFlag("string-value") as? String else {
                fail("Wrong type for flag")
                return
            }
            expect(flagValue) == "test"
        }

        it("returns payload - bool") {
            guard let flagValue = posthog.getFeatureFlagPayload("payload-bool") as? Bool else {
                return fail("Wrong type for flag")
            }
            expect(flagValue) == true
        }

        it("returns payload - number") {
            guard let flagValue = posthog.getFeatureFlagPayload("payload-number") as? Int else {
                return fail("Wrong type for flag")
            }
            expect(flagValue) == 2
        }

        it("returns payload - string") {
            guard let flagValue = posthog.getFeatureFlagPayload("payload-string") as? String else {
                return fail("Wrong type for flag")
            }
            expect(flagValue) == "string-value"
        }

        it("returns payload - dict") {
            guard let flagValue = posthog.getFeatureFlagPayload("payload-json") as? [String: String] else {
                return fail("Wrong type for flag")
            }
            expect(flagValue) == ["foo": "bar"]
        }

        it("returns nil for wrong type") {
            let flagValue = posthog.getFeatureFlagPayload("payload-json") as? String?
            expect(flagValue) == nil
        }
    }
}
