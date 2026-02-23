import Foundation
@testable import PostHog
import Testing

@Suite("Session Replay Sampling Tests")
class PostHogSamplingTests {
    // MARK: - simpleHash Tests

    @Test("simpleHash produces consistent values for the same input")
    func simpleHashConsistent() {
        let hash1 = simpleHash("test-session-id")
        let hash2 = simpleHash("test-session-id")
        #expect(hash1 == hash2)
    }

    @Test("simpleHash produces positive values")
    func simpleHashPositive() {
        let inputs = [
            "session-1",
            "session-2",
            "abc123",
            "00000000-0000-0000-0000-000000000000",
            UUID().uuidString,
        ]
        for input in inputs {
            #expect(simpleHash(input) >= 0, "Hash for '\(input)' should be non-negative")
        }
    }

    @Test("simpleHash produces distinct values for different inputs")
    func simpleHashDistinct() {
        let hash1 = simpleHash("session-1")
        let hash2 = simpleHash("session-2")
        #expect(hash1 != hash2)
    }

    @Test("simpleHash handles empty string")
    func simpleHashEmpty() {
        let hash = simpleHash("")
        #expect(hash == 0)
    }

    // MARK: - sampleOnProperty Tests

    @Test("sampleOnProperty returns true at rate 1.0")
    func sampleOnPropertyFullRate() {
        // At rate 1.0, all sessions should be sampled in
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", 1.0) == true)
        }
    }

    @Test("sampleOnProperty returns false at rate 0.0")
    func sampleOnPropertyZeroRate() {
        // At rate 0.0, no sessions should be sampled in
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", 0.0) == false)
        }
    }

    @Test("sampleOnProperty is deterministic")
    func sampleOnPropertyDeterministic() {
        let sessionId = "test-session-id-12345"
        let rate = 0.5
        let result1 = sampleOnProperty(sessionId, rate)
        let result2 = sampleOnProperty(sessionId, rate)
        #expect(result1 == result2)
    }

    @Test("sampleOnProperty clamps rate above 1.0")
    func sampleOnPropertyClampsAboveOne() {
        // Rate > 1.0 should be clamped to 1.0 (record all)
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", 1.5) == true)
        }
    }

    @Test("sampleOnProperty clamps rate below 0.0")
    func sampleOnPropertyClampsBelowZero() {
        // Rate < 0.0 should be clamped to 0.0 (record none)
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", -0.5) == false)
        }
    }

    @Test("sampleOnProperty samples approximately correct percentage")
    func sampleOnPropertyApproximateRate() {
        // With enough samples, ~50% should be sampled in at rate 0.5
        var sampledIn = 0
        let total = 1000
        for i in 0 ..< total {
            if sampleOnProperty("session-\(i)", 0.5) {
                sampledIn += 1
            }
        }
        // Allow generous tolerance since hash distribution may not be perfectly uniform
        let ratio = Double(sampledIn) / Double(total)
        #expect(ratio > 0.3, "Expected roughly 50% sampled in, got \(ratio * 100)%")
        #expect(ratio < 0.7, "Expected roughly 50% sampled in, got \(ratio * 100)%")
    }
}
