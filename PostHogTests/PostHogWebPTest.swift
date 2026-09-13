//
//  PostHogWebPTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/12/2024.
//

#if canImport(UIKit) || targetEnvironment(macCatalyst)
    import Foundation
    import Nimble
    @testable import PostHog
    import Quick
    import Testing
    import UIKit
    import XCTest

    // see: https://developers.google.com/speed/webp/gallery
    class PostHogWebPTest: QuickSpec {
        override func spec() {
            it("correctly encodes WebP image with -q 0.80") {
                let bundle = Bundle(for: type(of: self))
                let originalPath = bundle.path(forResource: "input_1", ofType: "png")
                let originalData = try! Data(contentsOf: URL(fileURLWithPath: originalPath!))
                let originalImage = UIImage(data: originalData)!

                let encodedPath = bundle.path(forResource: "output_1", ofType: "webp")
                let encodedData = try! Data(contentsOf: URL(fileURLWithPath: encodedPath!))

                // cwebp input_3.png -q 80 -preset default -o output_3.webp
                let sut = originalImage.webpData(
                    compressionQuality: 0.80
                )

                expect(sut).toNot(beNil())
                expect(sut).to(equal(encodedData))
            }

            it("correctly encodes WebP image with -q 0.30") {
                let bundle = Bundle(for: type(of: self))
                let originalPath = bundle.path(forResource: "input_2", ofType: "png")
                let originalData = try! Data(contentsOf: URL(fileURLWithPath: originalPath!))
                let originalImage = UIImage(data: originalData)!

                let encodedPath = bundle.path(forResource: "output_2", ofType: "webp")
                let encodedData = try! Data(contentsOf: URL(fileURLWithPath: encodedPath!))

                let sut = originalImage.webpData(compressionQuality: 0.30)

                expect(sut).toNot(beNil())
                expect(sut).to(equal(encodedData))
            }

            it("correctly encodes WebP image with alpha") {
                let bundle = Bundle(for: type(of: self))
                let originalPath = bundle.path(forResource: "input_3", ofType: "png")
                let originalData = try! Data(contentsOf: URL(fileURLWithPath: originalPath!))
                let originalImage = UIImage(data: originalData)!

                let encodedPath = bundle.path(forResource: "output_3", ofType: "webp")
                let encodedData = try! Data(contentsOf: URL(fileURLWithPath: encodedPath!))

                let sut = originalImage.webpData(compressionQuality: 0.80)

                expect(sut).toNot(beNil())
                expect(sut).to(equal(encodedData))
            }
        }
    }

    @Suite("WebP buffer ownership", .serialized)
    struct PostHogWebPBufferTests {
        @Test(arguments: [("1", CGFloat(0.8)), ("2", CGFloat(0.3)), ("3", CGFloat(0.8))])
        func encodedDataOutlivesEncoder(fixture: String, quality: CGFloat) throws {
            let bundle = Bundle(for: PostHogWebPTest.self)
            let inputURL = try #require(bundle.url(forResource: "input_\(fixture)", withExtension: "png"))
            let outputURL = try #require(bundle.url(forResource: "output_\(fixture)", withExtension: "webp"))
            let image = try #require(UIImage(data: Data(contentsOf: inputURL)))
            let expected = try Data(contentsOf: outputURL)
            let encoded = try #require(autoreleasepool { image.webpData(compressionQuality: quality) })

            for _ in 0 ..< 10 {
                let subsequent = autoreleasepool { image.webpData(compressionQuality: quality) }
                #expect(subsequent == expected)
            }
            #expect(encoded == expected)
            #expect(Data(base64Encoded: encoded.base64EncodedString()) == expected)
            #expect(image.toBase64(quality) == "data:image/webp;base64,\(expected.base64EncodedString())")

            var modified = encoded
            modified[0] ^= 0xFF
            #expect(encoded == expected)
            #expect(modified != encoded)
        }
    }

    #if WEBP_BENCHMARK
        final class PostHogWebPBenchmark: XCTestCase {
            @MainActor
            func testUI() throws {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844), format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
                    for row in 0 ..< 10 {
                        UIColor(red: 0.1, green: CGFloat(row) / 12, blue: 0.7, alpha: 1).setFill()
                        context.fill(CGRect(x: 16, y: 20 + row * 80, width: 358, height: 50))
                    }
                }
                try benchmark(image, quality: 0.3)
            }

            func testPhotoQuality30() throws {
                try benchmark(fixture("2"), quality: 0.3)
            }

            func testPhotoQuality80() throws {
                try benchmark(fixture("1"), quality: 0.8)
            }

            func testAlpha() throws {
                try benchmark(fixture("3"), quality: 0.8)
            }

            private func fixture(_ name: String) throws -> UIImage {
                let url = try XCTUnwrap(Bundle(for: PostHogWebPTest.self).url(forResource: "input_\(name)", withExtension: "png"))
                return try XCTUnwrap(UIImage(data: Data(contentsOf: url)))
            }

            private func benchmark(_ image: UIImage, quality: CGFloat) throws {
                let expected = try XCTUnwrap(image.toBase64(quality))
                let compressed = try XCTUnwrap(image.webpData(compressionQuality: quality))
                print("WEBP_BENCHMARK \(name) pixels=\(image.cgImage!.width)x\(image.cgImage!.height) compressedBytes=\(compressed.count)")
                for _ in 0 ..< 5 {
                    XCTAssertEqual(image.toBase64(quality), expected)
                }
                let options = XCTMeasureOptions()
                options.iterationCount = 20
                measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
                    autoreleasepool {
                        XCTAssertEqual(image.toBase64(quality), expected)
                    }
                }
            }
        }
    #endif
#endif
