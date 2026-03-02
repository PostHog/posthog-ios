//
//  PostHogSampling.swift
//  PostHog
//
//  Created on 23.02.26.
//

import Foundation

/// Deterministic hash function matching the JS SDK's `simpleHash`.
/// Uses 32-bit arithmetic and UTF-16 encoding to match JavaScript's
/// `charCodeAt` behavior (which returns UTF-16 code units).
func simpleHash(_ str: String) -> Int {
    var hash: Int32 = 0

    for codeUnit in str.utf16 {
        let codeUnitValue = Int32(codeUnit)
        hash = (hash &<< 5) &- hash &+ codeUnitValue // hash = hash * 31 + codeUnitValue, wrapping
    }

    // Match JS: return hash & 0x7fffffff
    return Int(hash & 0x7FFFFFFF)
}

/// Determines whether a property (typically a session ID) should be sampled in,
/// given a sampling rate between 0.0 and 1.0.
///
/// This matches the JS SDK's `sampleOnProperty` logic for deterministic,
/// consistent sampling across platforms.
///
/// - Parameters:
///   - prop: The property to hash (typically the session ID)
///   - percent: The sampling rate, between 0.0 (none) and 1.0 (all)
/// - Returns: `true` if the property should be sampled in (recorded)
func sampleOnProperty(_ prop: String, _ percent: Double) -> Bool {
    let clampedPercent = min(max(percent * 100, 0), 100)
    return Double(simpleHash(prop) % 100) < clampedPercent
}
