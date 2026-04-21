//
//  RageClickDetectorTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/04/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("RageClickDetector tests")
struct RageClickDetectorTest {
    // MARK: - Default configuration (3 taps, 30pt threshold, 1s timeout)

    @Test("Detects rage click after 3 rapid taps in same area")
    func detectsRageClick() {
        let detector = RageClickDetector()

        let results = [
            detector.isRageClick(x: 0, y: 0, timestamp: 0.010),
            detector.isRageClick(x: 10, y: 10, timestamp: 0.020),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.040), // triggers rage click
            detector.isRageClick(x: 5, y: 5, timestamp: 0.050), // does not re-trigger
        ]

        #expect(results == [false, false, true, false])
    }

    @Test("Re-triggers after temporal reset")
    func retriggersAfterTemporalReset() {
        let detector = RageClickDetector()

        let results = [
            detector.isRageClick(x: 0, y: 0, timestamp: 0.010),
            detector.isRageClick(x: 10, y: 10, timestamp: 0.020),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.040), // triggers rage click
            // these next three don't trigger because the click buffer is full
            detector.isRageClick(x: 5, y: 5, timestamp: 0.080),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.100),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.110),
            // time gap > 1s resets the counter
            detector.isRageClick(x: 5, y: 5, timestamp: 1.120),
            detector.isRageClick(x: 5, y: 5, timestamp: 1.121),
            detector.isRageClick(x: 5, y: 5, timestamp: 1.122), // triggers rage click
        ]

        #expect(results == [false, false, true, false, false, false, false, false, true])
    }

    @Test("Re-triggers after spatial reset")
    func retriggersAfterSpatialReset() {
        let detector = RageClickDetector()

        let results = [
            detector.isRageClick(x: 0, y: 0, timestamp: 0.010),
            detector.isRageClick(x: 10, y: 10, timestamp: 0.020),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.040), // triggers rage click
            // these next three don't trigger
            detector.isRageClick(x: 5, y: 5, timestamp: 0.080),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.100),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.110),
            // moving past the pixel threshold resets the counter
            detector.isRageClick(x: 36, y: 5, timestamp: 0.120),
            detector.isRageClick(x: 36, y: 5, timestamp: 0.130),
            detector.isRageClick(x: 36, y: 5, timestamp: 0.140), // triggers rage click
        ]

        #expect(results == [false, false, true, false, false, false, false, false, true])
    }

    @Test("Does not capture taps too far apart in time")
    func noDetectionWhenTooFarInTime() {
        let detector = RageClickDetector()

        detector.isRageClick(x: 5, y: 5, timestamp: 0.010)
        detector.isRageClick(x: 5, y: 5, timestamp: 0.020)
        let result = detector.isRageClick(x: 5, y: 5, timestamp: 4.000) // 4 seconds later

        #expect(result == false)
    }

    @Test("Does not capture taps too far apart in space")
    func noDetectionWhenTooFarInSpace() {
        let detector = RageClickDetector()

        detector.isRageClick(x: 0, y: 0, timestamp: 0.010)
        detector.isRageClick(x: 10, y: 10, timestamp: 0.020)
        let result = detector.isRageClick(x: 50, y: 10, timestamp: 0.040) // 50 > 30 threshold

        #expect(result == false)
    }

    @Test("Reset clears the click buffer")
    func resetClearsBuffer() {
        let detector = RageClickDetector()

        detector.isRageClick(x: 5, y: 5, timestamp: 0.010)
        detector.isRageClick(x: 5, y: 5, timestamp: 0.020)

        detector.reset()

        // After reset, need 3 new taps to trigger
        let results = [
            detector.isRageClick(x: 5, y: 5, timestamp: 0.030),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.040),
            detector.isRageClick(x: 5, y: 5, timestamp: 0.050), // triggers
        ]

        #expect(results == [false, false, true])
    }

    // MARK: - Custom configuration

    @Test("Respects custom tap count")
    func customTapCount() {
        let config = PostHogRageClickConfig()
        config.minimumTapCount = 2
        let detector = RageClickDetector(config: config)

        let results = [
            detector.isRageClick(x: 0, y: 0, timestamp: 0),
            detector.isRageClick(x: 0, y: 0, timestamp: 0.100), // triggers at 2 taps
        ]

        #expect(results == [false, true])
    }

    @Test("Respects custom timeout")
    func customTimeout() {
        let config = PostHogRageClickConfig()
        config.timeoutInterval = 0.1
        let detector = RageClickDetector(config: config)

        detector.isRageClick(x: 0, y: 0, timestamp: 0)
        detector.isRageClick(x: 0, y: 0, timestamp: 0.050)
        // next tap too late (after 100ms timeout)
        let result = detector.isRageClick(x: 0, y: 0, timestamp: 0.500)

        #expect(result == false)
    }

    @Test("Respects custom threshold")
    func customThreshold() {
        let config = PostHogRageClickConfig()
        config.thresholdPoints = 5
        let detector = RageClickDetector(config: config)

        detector.isRageClick(x: 0, y: 0, timestamp: 0)
        detector.isRageClick(x: 6, y: 0, timestamp: 0.050) // 6 > 5 threshold → resets
        let result = detector.isRageClick(x: 6, y: 0, timestamp: 0.080)

        #expect(result == false)
    }
}
