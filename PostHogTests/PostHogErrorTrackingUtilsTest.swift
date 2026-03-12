//
//  PostHogErrorTrackingUtilsTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 22/12/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogErrorTrackingUtils Tests")
struct PostHogErrorTrackingUtilsTest {
    // MARK: - UUID Formatting Tests

    @Suite("UUID Formatting")
    struct UUIDFormattingTests {
        @Test("formats UUID without hyphens")
        func formatsUUIDWithoutHyphens() {
            let input = "A1B2C3D4E5F67890ABCDEF1234567890"
            let expected = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"

            #expect(input.formattedAsUUID == expected)
        }

        @Test("preserves already formatted UUID")
        func preservesFormattedUUID() {
            let input = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
            let expected = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"

            #expect(input.formattedAsUUID == expected)
        }

        @Test("uppercases lowercase UUID")
        func uppercasesLowercaseUUID() {
            let input = "a1b2c3d4e5f67890abcdef1234567890"
            let expected = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"

            #expect(input.formattedAsUUID == expected)
        }

        @Test("returns original for invalid length")
        func returnsOriginalForInvalidLength() {
            let input = "tooshort"

            #expect(input.formattedAsUUID == input)
        }

        @Test("handles mixed case UUID")
        func handlesMixedCaseUUID() {
            let input = "a1B2c3D4-e5F6-7890-AbCd-Ef1234567890"
            let expected = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"

            #expect(input.formattedAsUUID == expected)
        }
    }

    // MARK: - CPU Architecture Tests

    @Suite("CPU Architecture")
    struct CPUArchitectureTests {
        @Test("returns arm64 for ARM64 CPU type")
        func returnsArm64() {
            let arch = PostHogCPUArchitecture.archName(cpuType: 0x0100_000C, cpuSubtype: 0)
            #expect(arch == "arm64")
        }

        @Test("returns x86_64 for x86_64 CPU type")
        func returnsX86_64() {
            let arch = PostHogCPUArchitecture.archName(cpuType: 0x0100_0007, cpuSubtype: 0)
            #expect(arch == "x86_64")
        }

        @Test("returns armv7 for ARM CPU type with subtype 9")
        func returnsArmv7() {
            let arch = PostHogCPUArchitecture.archName(cpuType: 12, cpuSubtype: 9)
            #expect(arch == "armv7")
        }

        @Test("returns armv7s for ARM CPU type with subtype 11")
        func returnsArmv7s() {
            let arch = PostHogCPUArchitecture.archName(cpuType: 12, cpuSubtype: 11)
            #expect(arch == "armv7s")
        }

        @Test("returns arm for ARM CPU type with unknown subtype")
        func returnsArmForUnknownSubtype() {
            let arch = PostHogCPUArchitecture.archName(cpuType: 12, cpuSubtype: 99)
            #expect(arch == "arm")
        }

        @Test("returns nil for unknown CPU type")
        func returnsNilForUnknownType() {
            let arch = PostHogCPUArchitecture.archName(cpuType: 999, cpuSubtype: 0)
            #expect(arch == nil)
        }
    }
}
