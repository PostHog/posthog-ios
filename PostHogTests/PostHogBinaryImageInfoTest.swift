//
//  PostHogBinaryImageInfoTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogBinaryImageInfo Tests")
struct PostHogBinaryImageInfoTest {
    static func expectRequiredKeys(_ dict: [String: Any], codeFile: String) {
        #expect(dict["type"] as? String == "macho")
        #expect(dict["code_file"] as? String == codeFile)
        #expect(dict["image_addr"] as? String == "0x000000018a3f0000")
        #expect(dict["image_size"] as? UInt64 == 0x4_0000)
    }

    @Suite("toDictionary")
    struct ToDictionaryTests {
        @Test("includes all fields when everything is set")
        func includesAllFields() {
            let image = PostHogBinaryImageInfo(
                name: "/private/var/containers/Bundle/Application/1A2B3C4D/MyApp.app/MyApp",
                uuid: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
                vmAddress: 0x1_0000_0000,
                address: 0x1_0234_C000,
                size: 0x8_0000,
                arch: "arm64"
            )

            let dict = image.toDictionary

            #expect(dict["type"] as? String == "macho")
            #expect(dict["code_file"] as? String == "/private/var/containers/Bundle/Application/1A2B3C4D/MyApp.app/MyApp")
            #expect(dict["image_addr"] as? String == "0x000000010234c000")
            #expect(dict["image_size"] as? UInt64 == 0x8_0000)
            #expect(dict["debug_id"] as? String == "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
            #expect(dict["image_vmaddr"] as? String == "0x0000000100000000")
            #expect(dict["arch"] as? String == "arm64")
            #expect(dict.count == 7)
        }

        @Test("only includes required fields when all optionals are nil")
        func onlyRequiredFieldsWhenOptionalsNil() {
            let image = PostHogBinaryImageInfo(
                name: "/usr/lib/system/libsystem_kernel.dylib",
                uuid: nil,
                vmAddress: nil,
                address: 0x1_8A3F_0000,
                size: 0x4_0000,
                arch: nil
            )

            let dict = image.toDictionary

            #expect(Set(dict.keys) == ["type", "code_file", "image_addr", "image_size"])
            PostHogBinaryImageInfoTest.expectRequiredKeys(dict, codeFile: "/usr/lib/system/libsystem_kernel.dylib")
            #expect(!dict.values.contains { $0 is NSNull })
        }

        @Test("includes only debug_id when it is the only optional set")
        func onlyDebugId() {
            let image = PostHogBinaryImageInfo(
                name: "/usr/lib/libobjc.A.dylib",
                uuid: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0",
                vmAddress: nil,
                address: 0x1_8A3F_0000,
                size: 0x4_0000,
                arch: nil
            )

            let dict = image.toDictionary

            PostHogBinaryImageInfoTest.expectRequiredKeys(dict, codeFile: "/usr/lib/libobjc.A.dylib")
            #expect(dict["debug_id"] as? String == "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")
            #expect(dict["image_vmaddr"] == nil)
            #expect(dict["arch"] == nil)
            #expect(dict.count == 5)
        }

        @Test("includes only arch when it is the only optional set", arguments: ["arm64", "x86_64", "arm64e"])
        func onlyArch(arch: String) {
            let image = PostHogBinaryImageInfo(
                name: "/usr/lib/libobjc.A.dylib",
                uuid: nil,
                vmAddress: nil,
                address: 0x1_8A3F_0000,
                size: 0x4_0000,
                arch: arch
            )

            let dict = image.toDictionary

            PostHogBinaryImageInfoTest.expectRequiredKeys(dict, codeFile: "/usr/lib/libobjc.A.dylib")
            #expect(dict["arch"] as? String == arch)
            #expect(dict["debug_id"] == nil)
            #expect(dict["image_vmaddr"] == nil)
            #expect(dict.count == 5)
        }

        @Test("includes only image_vmaddr when it is the only optional set")
        func onlyVmAddress() {
            let image = PostHogBinaryImageInfo(
                name: "/usr/lib/libobjc.A.dylib",
                uuid: nil,
                vmAddress: 0x1_0000_0000,
                address: 0x1_8A3F_0000,
                size: 0x4_0000,
                arch: nil
            )

            let dict = image.toDictionary

            #expect(dict["image_vmaddr"] as? String == "0x0000000100000000")
            #expect(dict["debug_id"] == nil)
            #expect(dict["arch"] == nil)
            #expect(dict.count == 5)
        }

        @Test("omits image_vmaddr when vmAddress is zero")
        func omitsZeroVmAddress() {
            let image = PostHogBinaryImageInfo(
                name: "/usr/lib/libobjc.A.dylib",
                uuid: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0",
                vmAddress: 0,
                address: 0x1_8A3F_0000,
                size: 0x4_0000,
                arch: "arm64"
            )

            let dict = image.toDictionary

            PostHogBinaryImageInfoTest.expectRequiredKeys(dict, codeFile: "/usr/lib/libobjc.A.dylib")
            #expect(dict["debug_id"] as? String == "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")
            #expect(dict["arch"] as? String == "arm64")
            #expect(dict["image_vmaddr"] == nil)
            #expect(dict.count == 6)
        }
    }
}
