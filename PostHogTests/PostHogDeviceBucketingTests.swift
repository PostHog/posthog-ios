//
//  PostHogDeviceBucketingTests.swift
//  PostHog
//
//  Created by Dylan Martin on 2026-04-08.
//

import Foundation
@testable import PostHog
import Testing
import XCTest

@Suite("Device bucketing tests", .serialized)
class PostHogDeviceBucketingTests {
    let server: MockPostHogServer

    var cleanupJobs: [() -> Void]

    func getSut(
        projectToken: String = UUID().uuidString,
        reuseAnonymousId: Bool = false,
        flushAt: Int = 1
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: projectToken, host: "http://localhost:9001")
        config.captureApplicationLifecycleEvents = false
        config.reuseAnonymousId = reuseAnonymousId
        config.flushAt = flushAt
        config.maxBatchSize = flushAt
        config.disableFlushOnBackgroundForTesting = true
        config.disableQueueTimerForTesting = true
        config.remoteConfig = false
        config.preloadFeatureFlags = false
        let sut = PostHogSDK.with(config)
        cleanupJobs.append {
            sut.close()
            deleteSafely(applicationSupportDirectoryURL().appendingPathComponent(projectToken))
        }
        return sut
    }

    init() throws {
        server = MockPostHogServer()
        server.start()
        cleanupJobs = []
    }

    deinit {
        for cleanup in cleanupJobs {
            cleanup()
        }
        server.stop()
    }

    @Test("initializes device_id on first setup")
    func initializesDeviceIdOnFirstSetup() {
        let sut = getSut()
        let deviceId = sut.getDeviceId()
        #expect(!deviceId.isEmpty)
        #expect(deviceId == sut.getAnonymousId())
    }

    @Test("preserves device_id across identify()")
    func preservesDeviceIdAcrossIdentify() {
        let sut = getSut()
        let originalDeviceId = sut.getDeviceId()

        sut.identify("user-123")

        #expect(sut.getDeviceId() == originalDeviceId)
        #expect(sut.getDistinctId() == "user-123")
    }

    @Test("preserves device_id across reset()")
    func preservesDeviceIdAcrossReset() {
        let sut = getSut()
        let originalDeviceId = sut.getDeviceId()

        sut.identify("user-123")
        sut.reset()

        #expect(sut.getDeviceId() == originalDeviceId)
        // distinct_id should have changed back to a new anonymous ID
        #expect(sut.getDistinctId() != "user-123")
    }

    @Test("preserves device_id across multiple identify/reset cycles")
    func preservesDeviceIdAcrossMultipleCycles() {
        let sut = getSut()
        let originalDeviceId = sut.getDeviceId()

        sut.identify("user-1")
        sut.reset()
        sut.identify("user-2")
        sut.reset()

        #expect(sut.getDeviceId() == originalDeviceId)
    }

    @Test("sends $device_id in feature flag requests")
    func sendsDeviceIdInFlagRequests() async throws {
        let projectToken = UUID().uuidString
        let sut = getSut(projectToken: projectToken)
        let deviceId = sut.getDeviceId()

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags {
                continuation.resume()
            }
        }

        let ownRequest = try #require(server.flagsRequests.compactMap { server.parseRequest($0, gzip: false) }.last { $0["api_key"] as? String == projectToken })
        #expect(ownRequest["$device_id"] as? String == deviceId)
    }

    @Test("sends the same $device_id after identify()")
    func sendsSameDeviceIdAfterIdentify() async throws {
        let projectToken = UUID().uuidString
        let sut = getSut(projectToken: projectToken)
        let deviceId = sut.getDeviceId()

        sut.identify("user-123")

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags {
                continuation.resume()
            }
        }

        let ownRequest = try #require(server.flagsRequests.compactMap { server.parseRequest($0, gzip: false) }.last { $0["api_key"] as? String == projectToken })
        #expect(ownRequest["$device_id"] as? String == deviceId)
        #expect(ownRequest["distinct_id"] as? String == "user-123")
    }

    @Test("persists device_id across SDK restarts")
    func persistsDeviceIdAcrossSdkRestarts() {
        let projectToken = UUID().uuidString
        var sut = getSut(projectToken: projectToken)
        let originalDeviceId = sut.getDeviceId()
        sut.close()

        // Re-init with same storage (same project token hits the same storage path)
        sut = getSut(projectToken: projectToken)
        #expect(sut.getDeviceId() == originalDeviceId)
    }
}
