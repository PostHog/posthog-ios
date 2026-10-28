#if os(iOS)
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay screenshot size", .serialized)
    @MainActor
    struct PostHogReplayScreenshotSizeTest {
        private static let secretRect = CGRect(x: 40, y: 60, width: 100, height: 80)

        private func window() throws -> UIWindow {
            let root = UIViewController()
            root.view.backgroundColor = .white
            let secret = UIView(frame: Self.secretRect)
            secret.backgroundColor = .red
            root.view.addSubview(secret)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.rootViewController = root
            window.makeKeyAndVisible()
            root.view.frame = window.bounds
            // On a 1x screen the native render is already one pixel per point, so nothing would be tested.
            try #require(window.screen.scale > 1)
            return window
        }

        private func uploaded(_ image: UIImage, masks: [CGRect]) throws -> CGImage {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = image
            wireframe.maskableWidgets = masks
            return try decode(wireframe)
        }

        private func decode(_ wireframe: RRWireframe) throws -> CGImage {
            let base64 = try #require(wireframe.toDict()["base64"] as? String)
            let encoded = try #require(base64.split(separator: ",").last.map(String.init))
            let data = try #require(Data(base64Encoded: encoded))
            return try #require(UIImage(data: data)?.cgImage)
        }

        private func pixelSize(_ image: CGImage) -> CGSize {
            CGSize(width: image.width, height: image.height)
        }

        /// Reads the pixel at `point` taken as pixel coordinates, not scaled to the image size.
        private func rgb(_ image: CGImage, at point: CGPoint) throws -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let x = Int(point.x), y = Int(point.y)
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
            return Array(rgba.prefix(3))
        }

        private func isRed(_ rgb: [UInt8]) -> Bool {
            rgb[0] > 180 && rgb[1] < 90 && rgb[2] < 90
        }

        private func isBlack(_ rgb: [UInt8]) -> Bool {
            rgb.allSatisfy { $0 < 50 }
        }

        private func isWhite(_ rgb: [UInt8]) -> Bool {
            rgb.allSatisfy { $0 > 200 }
        }

        @Test("an unmasked frame uploads at one pixel per point from every renderer")
        func unmaskedUploadIsOnePixelPerPoint() throws {
            let window = try window()
            defer { window.isHidden = true }
            let renders = [
                window.toImage(preferFidelityRenderer: false),
                window.toImage(preferFidelityRenderer: true),
                window.toImage(afterScreenUpdates: true),
            ]
            for render in renders {
                let image = try #require(render)
                #expect(try pixelSize(uploaded(image, masks: [])) == window.bounds.size)
            }
        }

        @Test("a wireframe-mode image uploads at its own size")
        func wireframeImageKeepsItsSize() throws {
            let window = try window()
            defer { window.isHidden = true }
            let image = try #require(window.toImage(preferFidelityRenderer: false))
            let wireframe = RRWireframe()
            wireframe.type = "image"
            wireframe.image = image
            let uploaded = try decode(wireframe)
            #expect(uploaded.width == image.cgImage?.width)
            #expect(uploaded.height == image.cgImage?.height)
        }

        @Test("a masked frame uploads at the unmasked size, with the mask on the secret's pixels")
        func maskLandsOnUnmaskedPixels() throws {
            let window = try window()
            defer { window.isHidden = true }
            let image = try #require(window.toImage(preferFidelityRenderer: false))
            let unmasked = try uploaded(image, masks: [])
            let masked = try uploaded(image, masks: [Self.secretRect])
            #expect(pixelSize(masked) == pixelSize(unmasked))

            let rect = Self.secretRect
            let inside = [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.minX + 12, y: rect.minY + 12),
                          CGPoint(x: rect.maxX - 12, y: rect.maxY - 12)]
            for point in inside {
                #expect(try isRed(rgb(unmasked, at: point)), "unmasked frame at \(point)")
                #expect(try isBlack(rgb(masked, at: point)), "masked frame at \(point)")
            }

            let outside = [CGPoint(x: rect.minX - 8, y: rect.midY), CGPoint(x: rect.maxX + 8, y: rect.midY),
                           CGPoint(x: rect.midX, y: rect.maxY + 8)]
            for point in outside {
                #expect(try isWhite(rgb(unmasked, at: point)), "unmasked frame at \(point)")
                #expect(try isWhite(rgb(masked, at: point)), "masked frame at \(point)")
            }
        }
    }
#endif
