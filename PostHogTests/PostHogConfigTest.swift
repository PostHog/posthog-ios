//
//  PostHogConfigTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogConfigTest: QuickSpec {
    override func spec() {
        it("init config with default values") {
            let config = PostHogConfig(projectToken: testProjectToken)

            expect(config.host) == URL(string: PostHogConfig.defaultHost)
            expect(config.flushAt) == 20
            expect(config.maxQueueSize) == 1000
            expect(config.maxBatchSize) == 50
            expect(config.flushIntervalSeconds) == 30
            expect(config.dataMode) == .any
            expect(config.sendFeatureFlagEvent) == true
            expect(config.preloadFeatureFlags) == true
            expect(config.captureApplicationLifecycleEvents) == true
            expect(config.captureScreenViews) == true
            expect(config.debug) == false
            expect(config.optOut) == false
        }

        it("init takes project token") {
            let config = PostHogConfig(projectToken: testProjectToken)

            expect(config.projectToken) == testProjectToken
            expect(config.apiKey) == testProjectToken
        }

        it("trims whitespace-sensitive config values") {
            let config = PostHogConfig(
                projectToken: " \n\(testProjectToken)\t ",
                host: " \nhttps://eu.i.posthog.com/\t "
            )

            expect(config.projectToken) == testProjectToken
            expect(config.apiKey) == testProjectToken
            expect(config.host) == URL(string: "https://eu.i.posthog.com/")
        }

        it("defaults a blank host after trimming whitespace") {
            let config = PostHogConfig(projectToken: testProjectToken, host: " \n\t ")

            expect(config.host) == URL(string: PostHogConfig.defaultHost)
        }

        it("init takes host") {
            let config = PostHogConfig(projectToken: testProjectToken, host: "localhost:9000")

            expect(config.host) == URL(string: "localhost:9000")!
        }

        #if os(iOS)
            context("when initialized with default values for captureElementInteractions") {
                it("should enable autocapture by default") {
                    let sut = PostHogConfig(projectToken: testProjectToken)
                    expect(sut.captureElementInteractions).to(beFalse())
                }
            }

            context("when customized") {
                it("should allow disabling autocapture") {
                    let config = PostHogConfig(projectToken: testProjectToken)
                    config.captureElementInteractions = false
                    expect(config.captureElementInteractions).to(beFalse())
                }
            }
        #endif
    }
}
