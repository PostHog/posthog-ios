//
//  RRWireframeTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing
#if os(iOS)
    import UIKit
#endif

@Suite("RRWireframe Tests")
struct RRWireframeTest {
    // A tiny base64 data URL as produced by `UIImage.toBase64()`.
    static let base64Image = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/"

    static func makeWireframe() -> RRWireframe {
        let wireframe = RRWireframe()
        wireframe.id = 42
        wireframe.posX = 16
        wireframe.posY = 120
        wireframe.width = 343
        wireframe.height = 44
        return wireframe
    }

    @Suite("toDict")
    struct ToDictTests {
        @Test("only produces the required geometry keys when nothing else is set")
        func onlyRequiredKeysWhenNothingSet() {
            let dict = RRWireframe().toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height"])
            #expect(dict["id"] as? Int == 0)
            #expect(dict["x"] as? Int == 0)
            #expect(dict["y"] as? Int == 0)
            #expect(dict["width"] as? Int == 0)
            #expect(dict["height"] as? Int == 0)
        }

        @Test("always includes the required geometry keys with their values")
        func includesRequiredKeys() {
            let dict = RRWireframeTest.makeWireframe().toDict()

            #expect(dict["id"] as? Int == 42)
            #expect(dict["x"] as? Int == 16)
            #expect(dict["y"] as? Int == 120)
            #expect(dict["width"] as? Int == 343)
            #expect(dict["height"] as? Int == 44)
            #expect(dict.count == 5)
        }

        @Test("a single optional field only produces its own key", arguments: [
            ("type", { (w: RRWireframe) in w.type = "screenshot" }, "screenshot"),
            ("base64", { (w: RRWireframe) in w.base64 = RRWireframeTest.base64Image }, RRWireframeTest.base64Image),
        ])
        func singleFieldOnlyProducesItsOwnKey(key: String, set: (RRWireframe) -> Void, expected: String) {
            let wireframe = RRWireframe()
            set(wireframe)

            let dict = wireframe.toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height", key])
            #expect(dict[key].map { String(describing: $0) } == expected)
            #expect(dict["id"] as? Int == 0)
        }

        @Test("includes the screenshot type and image")
        func includesScreenshotFields() {
            let wireframe = RRWireframeTest.makeWireframe()
            wireframe.type = "screenshot"
            wireframe.base64 = RRWireframeTest.base64Image

            let dict = wireframe.toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height", "type", "base64"])
            #expect(dict["type"] as? String == "screenshot")
            #expect(dict["base64"] as? String == RRWireframeTest.base64Image)
            #expect(!dict.values.contains { $0 is NSNull })
        }
    }

    #if os(iOS)
        @Suite("maskImage")
        struct MaskImageTests {
            @Test("fills every pixel of a mask rect, including its corners")
            func fillsCorners() throws {
                let white = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
                }
                let rect = CGRect(x: 20, y: 20, width: 60, height: 40)

                let masked = try #require(RRWireframe.maskImage(white, maskableWidgets: [rect]))

                for corner in [CGPoint(x: 20, y: 20), CGPoint(x: 79, y: 20), CGPoint(x: 20, y: 59), CGPoint(x: 79, y: 59)] {
                    #expect(Self.red(of: masked, at: corner) == 0, "corner \(corner) is not masked")
                }
                for outside in [CGPoint(x: 19, y: 20), CGPoint(x: 80, y: 59), CGPoint(x: 20, y: 19), CGPoint(x: 79, y: 60)] {
                    #expect(Self.red(of: masked, at: outside) == 255, "mask spilled outside its rect at \(outside)")
                }
            }

            /// Red channel of the pixel at `point`, read by drawing the image into a 1x1 bitmap.
            private static func red(of image: UIImage, at point: CGPoint) -> UInt8? {
                guard let cgImage = image.cgImage else { return nil }
                var pixel = [UInt8](repeating: 0, count: 4)
                guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return nil }
                // CGContext's origin is bottom-left: shift so the target pixel lands on (0, 0).
                context.draw(cgImage, in: CGRect(x: -point.x, y: point.y - CGFloat(cgImage.height) + 1,
                                                 width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
                return pixel[0]
            }
        }
    #endif
}
