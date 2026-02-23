//
//  PostHogSampling.swift
//  PostHog
//
//  Created on 23.02.26.
//

import Foundation

/// Deterministic hash function matching the JS SDK's `simpleHash`.
/// Uses 32-bit arithmetic to match JavaScript's bitwise operation behavior.
func simpleHash(_ str: String) -> Int {
    var hash: Int32 = 0
    for scalar in str.unicodeScalars {
        let charValue = Int32(truncatingIfNeeded: scalar.value)
        hash = (hash &<< 5) &- hash &+ charValue
    }
    return abs(Int(hash))
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
