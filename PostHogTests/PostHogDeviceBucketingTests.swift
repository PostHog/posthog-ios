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
        reuseAnonymousId: Bool = false,
        flushAt: Int = 1
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.captureApplicationLifecycleEvents = false
        config.reuseAnonymousId = reuseAnonymousId
        config.flushAt = flushAt
        config.maxBatchSize = flushAt
        config.disableFlushOnBackgroundForTesting = true
        config.preloadFeatureFlags = false
        let sut = PostHogSDK.with(config)
        cleanupJobs.append {
            sut.reset()
            sut.close()
            deleteSafely(applicationSupportDirectoryURL())
        }
        return sut
    }

    init() throws {
        server = MockPostHogServer()
        server.start()
        cleanupJobs = []
    }

    deinit {
        server.reset()
        for cleanup in cleanupJobs {
            cleanup()
        }
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
    func sendsDeviceIdInFlagRequests() async {
        let sut = getSut()
        let deviceId = sut.getDeviceId()

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags {
                continuation.resume()
            }
        }

        #expect(server.flagsRequests.count > 0)

        guard let lastRequest = server.flagsRequests.last,
              let requestBody = server.parseRequest(lastRequest, gzip: false)
        else {
            #expect(Bool(false), "Failed to parse flags request")
            return
        }

        #expect(requestBody["$device_id"] as? String == deviceId)
    }

    @Test("sends the same $device_id after identify()")
    func sendsSameDeviceIdAfterIdentify() async {
        let sut = getSut()
        let deviceId = sut.getDeviceId()

        sut.identify("user-123")

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags {
                continuation.resume()
            }
        }

        #expect(server.flagsRequests.count > 0)

        guard let lastRequest = server.flagsRequests.last,
              let requestBody = server.parseRequest(lastRequest, gzip: false)
        else {
            #expect(Bool(false), "Failed to parse flags request")
            return
        }

        #expect(requestBody["$device_id"] as? String == deviceId)
    }

    @Test("persists device_id across SDK restarts")
    func persistsDeviceIdAcrossSdkRestarts() {
        var sut = getSut()
        let originalDeviceId = sut.getDeviceId()
        sut.close()

        // Re-init with same storage (same project token hits the same storage path)
        sut = getSut()
        #expect(sut.getDeviceId() == originalDeviceId)
    }
}
