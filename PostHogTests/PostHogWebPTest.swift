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
            it("correctly encodes WebP image with -q 0.80 -m 6 -f 60") {
                let bundle = Bundle(for: type(of: self))
                let originalPath = bundle.path(forResource: "input_1", ofType: "png")
                let originalData = try! Data(contentsOf: URL(fileURLWithPath: originalPath!))
                let originalImage = UIImage(data: originalData)!

                let encodedPath = bundle.path(forResource: "output_1", ofType: "webp")
                let encodedData = try! Data(contentsOf: URL(fileURLWithPath: encodedPath!))

                // cwebp input_3.png -q 80 -preset default -o output_3.webp
                let sut = originalImage.webpData(
                    compressionQuality: 0.80,
                    options: [
                        .method(6),
                        .filterStrength(60),
                    ]
                )

                expect(sut).toNot(beNil())
                expect(sut).to(equal(encodedData))
            }

            it("correctly encodes WebP image with -q 0.30 -m 4 -f 50") {
                let bundle = Bundle(for: type(of: self))
                let originalPath = bundle.path(forResource: "input_2", ofType: "png")
                let originalData = try! Data(contentsOf: URL(fileURLWithPath: originalPath!))
                let originalImage = UIImage(data: originalData)!

                let encodedPath = bundle.path(forResource: "output_2", ofType: "webp")
                let encodedData = try! Data(contentsOf: URL(fileURLWithPath: encodedPath!))

                let sut = originalImage.webpData(
                    compressionQuality: 0.30,
                    options: [
                        .method(4),
                        .filterStrength(50),
                    ]
                )

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

            it("should not crash when called with different options") {
                // Since we changed/removed some of the vendored code, let's test some combinations of options to make sure no assertions will be thrown. Alternatively, we may dig into vendored code and remove all asserts?
                let bundle = Bundle(for: type(of: self))
                let originalPath = bundle.path(forResource: "input_3", ofType: "png")
                let originalData = try! Data(contentsOf: URL(fileURLWithPath: originalPath!))
                let originalImage = UIImage(data: originalData)!

                let testWithOptions: (WebPOption...) -> Void = { options in
                    _ = originalImage.webpData(
                        compressionQuality: 0.80,
                        options: options
                    )
                }

                testWithOptions()

                testWithOptions(
                    .useSharpYUV(true)
                )

                testWithOptions(
                    .useDeltaPalette(true)
                )

                testWithOptions(
                    .lowMemory(true)
                )

                testWithOptions(
                    .segments(2),
                    .partitionLimit(4)
                )

                testWithOptions(
                    .preprocessing(true),
                    .showCompressed(true)
                )

                testWithOptions(
                    .passes(10),
                    .showCompressed(true)
                )

                testWithOptions(
                    .alphaCompression(1)
                )

                testWithOptions(
                    .autofilter(true)
                )

                testWithOptions(
                    .targetPSNR(43.3)
                )
            }
        }
    }
#endif
