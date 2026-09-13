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
#endif
