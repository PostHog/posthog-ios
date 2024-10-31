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
            let config = PostHogConfig(apiKey: "123")

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

        it("init takes api key") {
            let config = PostHogConfig(apiKey: "123")

            expect(config.apiKey) == "123"
        }

        it("init takes host") {
            let config = PostHogConfig(apiKey: "123", host: "localhost:9000")

            expect(config.host) == URL(string: "localhost:9000")!
        }

        #if os(iOS)
            context("when initialized with default values for autocapture") {
                it("should enable autocapture by default") {
                    let sut = PostHogConfig(apiKey: "123")
                    expect(sut.autocapture).to(beFalse())
                }

                it("should initialize autocaptureConfig with default values") {
                    let sut = PostHogConfig(apiKey: "123")
                    expect(sut.autocaptureConfig.captureGestures).to(beTrue())
                    expect(sut.autocaptureConfig.captureTextEdits).to(beTrue())
                    expect(sut.autocaptureConfig.captureControlActions).to(beTrue())
                    expect(sut.autocaptureConfig.captureValues).to(beTrue())
                }
            }

            context("when customized") {
                it("should allow disabling autocapture") {
                    let config = PostHogConfig(apiKey: "123")
                    config.autocapture = false
                    expect(config.autocapture).to(beFalse())
                }

                it("should allow changing autocaptureConfig properties") {
                    let sut = PostHogConfig(apiKey: "123")
                    sut.autocaptureConfig.captureValues = false
                    sut.autocaptureConfig.captureGestures = false
                    expect(sut.autocaptureConfig.captureGestures).to(beFalse())
                    expect(sut.autocaptureConfig.captureTextEdits).to(beTrue())
                    expect(sut.autocaptureConfig.captureControlActions).to(beTrue())
                    expect(sut.autocaptureConfig.captureValues).to(beFalse())
                }
            }
        #endif
    }
}
