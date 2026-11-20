//
//  PostHogWebPTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/12/2024.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay image encoding")
    struct PostHogReplayImageEncodingTests {
        @Test("encodes as WebP when libwebp is linked, JPEG otherwise")
        func encodesWithExpectedFormat() throws {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            #if !SWIFT_PACKAGE || SessionReplay
                let mimeType = "webp"
            #else
                let mimeType = "jpeg"
            #endif

            let encoded = try #require(image.toBase64())

            #expect(encoded.hasPrefix("data:image/\(mimeType);base64,"))
        }
    }
#endif

// Mirrors the gate on `UIImage.webpData`, which SwiftPM compiles out when the `SessionReplay` trait is off.
#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    // see: https://developers.google.com/speed/webp/gallery
    @Suite("PostHogWebP", .serialized, .resetsGlobalState)
    final class PostHogWebPTest {
        @Test("correctly encodes WebP image with -q 0.80")
        func encodesWebPQuality80() throws {
            let bundle = Bundle(for: type(of: self))
            let originalPath = try #require(bundle.path(forResource: "input_1", ofType: "png"))
            let originalData = try Data(contentsOf: URL(fileURLWithPath: originalPath))
            let originalImage = try #require(UIImage(data: originalData))

            let encodedPath = try #require(bundle.path(forResource: "output_1", ofType: "webp"))
            let encodedData = try Data(contentsOf: URL(fileURLWithPath: encodedPath))

            // cwebp input_3.png -q 80 -preset default -o output_3.webp
            let sut = originalImage.webpData(
                compressionQuality: 0.80
            )

            #expect(sut != nil)
            #expect(sut == encodedData)
        }

        @Test("correctly encodes WebP image with -q 0.30")
        func encodesWebPQuality30() throws {
            let bundle = Bundle(for: type(of: self))
            let originalPath = try #require(bundle.path(forResource: "input_2", ofType: "png"))
            let originalData = try Data(contentsOf: URL(fileURLWithPath: originalPath))
            let originalImage = try #require(UIImage(data: originalData))

            let encodedPath = try #require(bundle.path(forResource: "output_2", ofType: "webp"))
            let encodedData = try Data(contentsOf: URL(fileURLWithPath: encodedPath))

            let sut = originalImage.webpData(compressionQuality: 0.30)

            #expect(sut != nil)
            #expect(sut == encodedData)
        }

        @Test("correctly encodes WebP image with alpha")
        func encodesWebPWithAlpha() throws {
            let bundle = Bundle(for: type(of: self))
            let originalPath = try #require(bundle.path(forResource: "input_3", ofType: "png"))
            let originalData = try Data(contentsOf: URL(fileURLWithPath: originalPath))
            let originalImage = try #require(UIImage(data: originalData))

            let encodedPath = try #require(bundle.path(forResource: "output_3", ofType: "webp"))
            let encodedData = try Data(contentsOf: URL(fileURLWithPath: encodedPath))

            let sut = originalImage.webpData(compressionQuality: 0.80)

            #expect(sut != nil)
            #expect(sut == encodedData)
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

    @Suite("WebP color space")
    struct PostHogWebPColorSpaceTests {
        private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

        @Test("encodes a wide-gamut image in sRGB")
        func wideGamutEncodesInSRGB() {
            #expect(UIImage.webPColorSpace(for: displayP3).name == CGColorSpace.sRGB)
        }

        @Test("encodes an sRGB or device RGB image in its own color space")
        func standardGamutKeepsItsColorSpace() {
            let deviceRGB = CGColorSpaceCreateDeviceRGB()
            #expect(UIImage.webPColorSpace(for: sRGB) === sRGB)
            #expect(UIImage.webPColorSpace(for: deviceRGB) === deviceRGB)
        }

        @Test("encodes an image without an RGB color space in linear sRGB")
        func otherModelsEncodeInLinearSRGB() {
            #expect(UIImage.webPColorSpace(for: CGColorSpaceCreateDeviceGray()).name == CGColorSpace.linearSRGB)
            #expect(UIImage.webPColorSpace(for: nil).name == CGColorSpace.linearSRGB)
        }

        @Test("keeps a Display P3 image's colors when it is encoded")
        func displayP3ImageKeepsItsColors() throws {
            let fill = try #require(
                CGColor(colorSpace: sRGB, components: [0.8, 0.2, 0.2, 1])?
                    .converted(to: displayP3, intent: .defaultIntent, options: nil)
            )
            var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
            let source = try #require(CGContext(
                data: &pixels, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                space: displayP3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            source.setFillColor(fill)
            source.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            let image = try UIImage(cgImage: #require(source.makeImage()))

            let data = try #require(image.webpData(compressionQuality: 1))
            let decoded = try #require(UIImage(data: data)?.cgImage)
            var rgba = [UInt8](repeating: 0, count: 4)
            let reader = try #require(CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            reader.draw(decoded, in: CGRect(x: -16, y: -16, width: decoded.width, height: decoded.height))

            #expect(abs(Int(rgba[0]) - 204) <= 6)
            #expect(abs(Int(rgba[1]) - 51) <= 6)
            #expect(abs(Int(rgba[2]) - 51) <= 6)
        }
    }
#endif
