//
//  PostHogStackFrameTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogStackFrame Tests")
struct PostHogStackFrameTest {
    @Suite("toDictionary")
    struct ToDictionaryTests {
        @Test("includes all fields when everything is set")
        func includesAllFields() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: "MyApp",
                package: "com.example.MyApp",
                imageAddress: 0x1_0000_0000,
                inApp: true,
                function: "$s5MyApp4mainyyF",
                symbolAddress: 0x1_0000_0F00
            )

            let dict = frame.toDictionary

            #expect(dict["instruction_addr"] as? String == "0x0000000100001000")
            #expect(dict["platform"] as? String == "apple")
            #expect(dict["in_app"] as? Bool == true)
            #expect(dict["module"] as? String == "MyApp")
            #expect(dict["package"] as? String == "com.example.MyApp")
            #expect(dict["function"] as? String == "$s5MyApp4mainyyF")
            #expect(dict["image_addr"] as? String == "0x0000000100000000")
            #expect(dict["symbol_addr"] as? String == "0x0000000100000f00")
            #expect(dict.count == 8)
        }

        @Test("only includes required fields when all optionals are nil")
        func onlyRequiredFieldsWhenOptionalsNil() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: nil,
                package: nil,
                imageAddress: nil,
                inApp: false,
                function: nil,
                symbolAddress: nil
            )

            let dict = frame.toDictionary

            #expect(Set(dict.keys) == ["instruction_addr", "platform", "in_app"])
        }

        @Test("reports in_app for both values", arguments: [true, false])
        func reportsInApp(inApp: Bool) {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: nil,
                package: nil,
                imageAddress: nil,
                inApp: inApp,
                function: nil,
                symbolAddress: nil
            )

            let dict = frame.toDictionary

            #expect(dict["in_app"] as? Bool == inApp)
        }

        @Test("omits module when nil")
        func omitsNilModule() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: nil,
                package: "com.example.MyApp",
                imageAddress: 0x1_0000_0000,
                inApp: true,
                function: "$s5MyApp4mainyyF",
                symbolAddress: 0x1_0000_0F00
            )

            let dict = frame.toDictionary

            #expect(dict["module"] == nil)
            #expect(dict.count == 7)
        }

        @Test("omits package when nil")
        func omitsNilPackage() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: "MyApp",
                package: nil,
                imageAddress: 0x1_0000_0000,
                inApp: true,
                function: "$s5MyApp4mainyyF",
                symbolAddress: 0x1_0000_0F00
            )

            let dict = frame.toDictionary

            #expect(dict["package"] == nil)
            #expect(dict.count == 7)
        }

        @Test("omits function when nil")
        func omitsNilFunction() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: "MyApp",
                package: "com.example.MyApp",
                imageAddress: 0x1_0000_0000,
                inApp: true,
                function: nil,
                symbolAddress: 0x1_0000_0F00
            )

            let dict = frame.toDictionary

            #expect(dict["function"] == nil)
            #expect(dict.count == 7)
        }

        @Test("omits image_addr when imageAddress is nil")
        func omitsNilImageAddress() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: "MyApp",
                package: "com.example.MyApp",
                imageAddress: nil,
                inApp: true,
                function: "$s5MyApp4mainyyF",
                symbolAddress: 0x1_0000_0F00
            )

            let dict = frame.toDictionary

            #expect(dict["image_addr"] == nil)
            #expect(dict.count == 7)
        }

        @Test("omits symbol_addr when symbolAddress is nil")
        func omitsNilSymbolAddress() {
            let frame = PostHogStackFrame(
                instructionAddress: 0x1_0000_1000,
                module: "MyApp",
                package: "com.example.MyApp",
                imageAddress: 0x1_0000_0000,
                inApp: true,
                function: "$s5MyApp4mainyyF",
                symbolAddress: nil
            )

            let dict = frame.toDictionary

            #expect(dict["symbol_addr"] == nil)
            #expect(dict.count == 7)
        }

        @Test("formats addresses as zero-padded 16 digit hex", arguments: [
            (UInt64(0), "0x0000000000000000"),
            (UInt64(0xABC), "0x0000000000000abc"),
            (UInt64.max, "0xffffffffffffffff"),
        ])
        func formatsAddresses(address: UInt64, expected: String) {
            let frame = PostHogStackFrame(
                instructionAddress: address,
                module: nil,
                package: nil,
                imageAddress: address,
                inApp: true,
                function: nil,
                symbolAddress: address
            )

            let dict = frame.toDictionary

            #expect(dict["instruction_addr"] as? String == expected)
            #expect(dict["image_addr"] as? String == expected)
            #expect(dict["symbol_addr"] as? String == expected)
        }
    }
}
