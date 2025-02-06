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
    import UIKit

    // see: https://developers.google.com/speed/webp/gallery
    class PostHogWebPTest: QuickSpec {
        override func spec() {
            it("correctly encodes WebP image with -q 0.80") {
                let bundle = Bundle.test
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
                let bundle = Bundle.test
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
                let bundle = Bundle.test
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
#endif
