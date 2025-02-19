//
//  UtilsTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 07/02/2025.
//

import Foundation
import Testing

@testable import PostHog

@Suite("UtilsTest")
struct UtilsTest {
    @Suite("CGFloat Tests")
    struct CGFloatTests {
        @Test("safely converts NaN to Int")
        func safelyConvertsNanToInt() {
            let nanNumber = CGFloat.nan
            #expect(nanNumber.toInt() == 0)
        }

        @Test("safely converts Max to Int and deals with overflow")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = CGFloat.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == Int.max)
        }

        @Test("safely converts to Int and rounds value")
        func safelyConvertsToIntAndRoundsValue() {
            let frNumber: CGFloat = 1234567890.5
            #expect(frNumber.toInt() == 1234567891)
        }
    }

    @Suite("Double Tests")
    struct DoubleTests {
        @Test("safely converts NaN to Int")
        func safelyConvertsNanToInt() {
            let nanNumber = Double.nan
            #expect(nanNumber.toInt() == 0)
        }

        @Test("safely converts Max to Int and deals with overflow")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = Double.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == Int.max)
        }

        @Test("safely converts to Int and rounds value")
        func safelyConvertsToIntAndRoundsValue() {
            let frNumber = 1234567890.5
            #expect(frNumber.toInt() == 1234567891)
        }
    }
}
