//
//  PostHogDebugImageProviderTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 22/12/2025.
//

import Foundation
import Testing

@testable import PostHog

@Suite("PostHogDebugImageProvider Tests")
struct PostHogDebugImageProviderTest {
    // MARK: - Get All Binary Images Tests

    @Suite("Get All Binary Images")
    struct GetAllBinaryImagesTests {
        @Test("returns non-empty list of binary images")
        func returnsNonEmptyList() {
            let images = PostHogDebugImageProvider.getAllBinaryImages()

            #expect(images.count > 0)
        }

        @Test("includes main executable")
        func includesMainExecutable() {
            let images = PostHogDebugImageProvider.getAllBinaryImages()

            let hasExecutable = images.contains { image in
                image.name.contains("xctest") || image.name.contains("PostHog")
            }

            #expect(hasExecutable == true)
        }

        @Test("images have valid addresses")
        func imagesHaveValidAddresses() {
            let images = PostHogDebugImageProvider.getAllBinaryImages()

            for image in images {
                #expect(image.address > 0)
                #expect(image.size > 0)
            }
        }

        @Test("images have UUIDs")
        func imagesHaveUUIDs() {
            let images = PostHogDebugImageProvider.getAllBinaryImages()

            let imagesWithUUID = images.filter { $0.uuid != nil }
            #expect(imagesWithUUID.count > 0)
        }

        @Test("UUIDs are in correct format")
        func uuidsAreInCorrectFormat() {
            let images = PostHogDebugImageProvider.getAllBinaryImages()

            for image in images where image.uuid != nil {
                let uuid = image.uuid!
                let uuidPattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
                let regex = try? NSRegularExpression(pattern: uuidPattern)
                let range = NSRange(uuid.startIndex..., in: uuid)
                #expect(regex?.firstMatch(in: uuid, range: range) != nil)
            }
        }
    }

    // MARK: - Get Debug Images for Frames Tests

    @Suite("Get Debug Images for Frames")
    struct GetDebugImagesForFramesTests {
        @Test("returns debug images for valid frame addresses")
        func returnsDebugImagesForValidAddresses() {
            let allImages = PostHogDebugImageProvider.getAllBinaryImages()
            guard let firstImage = allImages.first else {
                Issue.record("No binary images found")
                return
            }

            let frames: [[String: Any]] = [
                ["image_addr": String(format: "0x%llx", firstImage.address)],
            ]

            let debugImages = PostHogDebugImageProvider.getDebugImages(for: frames)

            #expect(debugImages.count >= 1)
        }

        @Test("returns empty array for invalid addresses")
        func returnsEmptyForInvalidAddresses() {
            let frames: [[String: Any]] = [
                ["image_addr": "0x0"],
                ["image_addr": "0xdeadbeef"],
            ]

            let debugImages = PostHogDebugImageProvider.getDebugImages(for: frames)

            #expect(debugImages.count == 0)
        }

        @Test("returns empty array for empty frames")
        func returnsEmptyForEmptyFrames() {
            let frames: [[String: Any]] = []

            let debugImages = PostHogDebugImageProvider.getDebugImages(for: frames)

            #expect(debugImages.count == 0)
        }

        @Test("deduplicates images by address")
        func deduplicatesImagesByAddress() {
            let allImages = PostHogDebugImageProvider.getAllBinaryImages()
            guard let firstImage = allImages.first else {
                Issue.record("No binary images found")
                return
            }

            let address = String(format: "0x%llx", firstImage.address)
            let frames: [[String: Any]] = [
                ["image_addr": address],
                ["image_addr": address],
                ["image_addr": address],
            ]

            let debugImages = PostHogDebugImageProvider.getDebugImages(for: frames)

            #expect(debugImages.count == 1)
        }
    }

    // MARK: - Get Debug Images from Exceptions Tests

    @Suite("Get Debug Images from Exceptions")
    struct GetDebugImagesFromExceptionsTests {
        @Test("extracts debug images from exception list")
        func extractsDebugImagesFromExceptionList() {
            let allImages = PostHogDebugImageProvider.getAllBinaryImages()
            guard let firstImage = allImages.first else {
                Issue.record("No binary images found")
                return
            }

            let exceptions: [[String: Any]] = [
                [
                    "type": "TestException",
                    "stacktrace": [
                        "type": "raw",
                        "frames": [
                            ["image_addr": String(format: "0x%llx", firstImage.address)],
                        ],
                    ] as [String: Any],
                ],
            ]

            let debugImages = PostHogDebugImageProvider.getDebugImages(fromExceptions: exceptions)

            #expect(debugImages.count == 1)
        }

        @Test("handles exceptions without stacktrace")
        func handlesExceptionsWithoutStacktrace() {
            let exceptions: [[String: Any]] = [
                ["type": "TestException", "value": "No stacktrace"],
            ]

            let debugImages = PostHogDebugImageProvider.getDebugImages(fromExceptions: exceptions)

            #expect(debugImages.count == 0)
        }

        @Test("handles empty exception list")
        func handlesEmptyExceptionList() {
            let exceptions: [[String: Any]] = []

            let debugImages = PostHogDebugImageProvider.getDebugImages(fromExceptions: exceptions)

            #expect(debugImages.count == 0)
        }

        @Test("collects images from multiple exceptions")
        func collectsFromMultipleExceptions() {
            let allImages = PostHogDebugImageProvider.getAllBinaryImages()
            guard allImages.count >= 2 else {
                Issue.record("Need at least 2 binary images for this test")
                return
            }

            let exceptions: [[String: Any]] = [
                [
                    "type": "Exception1",
                    "stacktrace": [
                        "frames": [
                            ["image_addr": String(format: "0x%llx", allImages[0].address)],
                        ],
                    ] as [String: Any],
                ],
                [
                    "type": "Exception2",
                    "stacktrace": [
                        "frames": [
                            ["image_addr": String(format: "0x%llx", allImages[1].address)],
                        ],
                    ] as [String: Any],
                ],
            ]

            let debugImages = PostHogDebugImageProvider.getDebugImages(fromExceptions: exceptions)

            #expect(debugImages.count >= 2)
        }
    }

    // MARK: - Binary Image Info Dictionary Tests

    @Suite("Binary Image Info Dictionary")
    struct BinaryImageInfoDictionaryTests {
        @Test("omits nil UUID from dictionary")
        func omitsNilUUID() {
            let imageInfo = PostHogBinaryImageInfo(
                name: "/test.dylib",
                uuid: nil,
                vmAddress: 0x100_0000,
                address: 0x100_0000,
                size: 0x1000
            )

            let dict = imageInfo.toDictionary

            #expect(dict["debug_id"] == nil)
        }

        @Test("omits zero vmAddress from dictionary")
        func omitsZeroVmAddress() {
            let imageInfo = PostHogBinaryImageInfo(
                name: "/test.dylib",
                uuid: nil,
                vmAddress: 0,
                address: 0x100_0000,
                size: 0x1000
            )

            let dict = imageInfo.toDictionary

            #expect(dict["image_vmaddr"] == nil)
        }

        @Test("omits nil arch from dictionary")
        func omitsNilArch() {
            let imageInfo = PostHogBinaryImageInfo(
                name: "/test.dylib",
                uuid: nil,
                vmAddress: nil,
                address: 0x100_0000,
                size: 0x1000,
                arch: nil
            )

            let dict = imageInfo.toDictionary

            #expect(dict["arch"] == nil)
        }
    }
}
