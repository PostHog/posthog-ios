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

        private func uploaded(_ image: UIImage, masks: [CGRect], pixelScale: CGFloat = 1) throws -> CGImage {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = image
            wireframe.maskableWidgets = masks
            wireframe.screenshotPixelScale = pixelScale
            return try decode(wireframe)
        }

        private func pixelScale(screenshotScale: NSNumber?, on window: UIWindow) -> CGFloat {
            let config = PostHogSessionReplayConfig()
            config.screenshotScale = screenshotScale
            return config.screenshotPixelScale(nativeScale: window.screen.scale)
        }

        private func solidImage(_ color: UIColor, size: CGSize, scale: CGFloat) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
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

        @Test("an unset screenshotScale uploads one pixel per point")
        func nilScaleUploadsPointSize() throws {
            let window = try window()
            defer { window.isHidden = true }
            let image = try #require(window.toImage(preferFidelityRenderer: false))
            let scale = pixelScale(screenshotScale: nil, on: window)
            #expect(scale == 1)
            #expect(try pixelSize(uploaded(image, masks: [], pixelScale: scale)) == window.bounds.size)
            #expect(try pixelSize(uploaded(image, masks: [Self.secretRect], pixelScale: scale)) == window.bounds.size)
        }

        @Test("screenshotScale uploads that fraction of native resolution, masked or not", arguments: [0.5, 1.0])
        func explicitScaleUploadsFractionOfNative(screenshotScale: Double) throws {
            let window = try window()
            defer { window.isHidden = true }
            let image = try #require(window.toImage(preferFidelityRenderer: false))
            let scale = pixelScale(screenshotScale: NSNumber(value: screenshotScale), on: window)
            #expect(scale == window.screen.scale * CGFloat(screenshotScale))

            let expected = CGSize(width: (window.bounds.width * scale).rounded(.up),
                                  height: (window.bounds.height * scale).rounded(.up))
            #expect(try pixelSize(uploaded(image, masks: [], pixelScale: scale)) == expected)
            #expect(try pixelSize(uploaded(image, masks: [Self.secretRect], pixelScale: scale)) == expected)
        }

        @Test("screenshotScale is clamped to 0.1...1, and NaN or infinity unset it",
              arguments: [(0.7, 0.7), (0.01, 0.1), (-1, 0.1), (5, 1), (.nan, nil), (.infinity, nil), (-.infinity, nil)] as [(Double, Double?)])
        func screenshotScaleIsClamped(value: Double, expected: Double?) {
            let config = PostHogSessionReplayConfig()
            config.screenshotScale = NSNumber(value: value)
            #expect(config.screenshotScale?.doubleValue == expected)
        }

        @Test("a fractional output size rounds up and leaves no pixel undrawn")
        func fractionalSizeRoundsUp() throws {
            let image = solidImage(.white, size: CGSize(width: 201, height: 301), scale: 3)
            let uploaded = try uploaded(image, masks: [], pixelScale: 1.5)
            #expect(pixelSize(uploaded) == CGSize(width: 302, height: 452))
            #expect(try isWhite(rgb(uploaded, at: CGPoint(x: 301, y: 451))))
        }

        @Test("a mask lands on the secret's pixels at a non-1x scale")
        func maskLandsAtNonUnitScale() throws {
            let window = try window()
            defer { window.isHidden = true }
            let image = try #require(window.toImage(preferFidelityRenderer: false))
            let scale = pixelScale(screenshotScale: 0.5, on: window)
            let unmasked = try uploaded(image, masks: [], pixelScale: scale)
            let masked = try uploaded(image, masks: [Self.secretRect], pixelScale: scale)

            let rect = Self.secretRect
            let inside = [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.minX + 12, y: rect.minY + 12),
                          CGPoint(x: rect.maxX - 12, y: rect.maxY - 12)]
            for point in inside {
                let pixel = CGPoint(x: point.x * scale, y: point.y * scale)
                #expect(try isRed(rgb(unmasked, at: pixel)), "unmasked frame at \(point)")
                #expect(try isBlack(rgb(masked, at: pixel)), "masked frame at \(point)")
            }

            let outside = [CGPoint(x: rect.minX - 8, y: rect.midY), CGPoint(x: rect.maxX + 8, y: rect.midY),
                           CGPoint(x: rect.midX, y: rect.maxY + 8)]
            for point in outside {
                let pixel = CGPoint(x: point.x * scale, y: point.y * scale)
                #expect(try isWhite(rgb(masked, at: pixel)), "masked frame at \(point)")
            }
        }

        @Test("a mask edge that falls mid-pixel covers that whole native pixel")
        func maskEdgeRoundsOutward() throws {
            let image = solidImage(.red, size: CGSize(width: 200, height: 300), scale: 3)
            // At 3 pixels per point these edges land on pixels 120.3 and 419.7.
            let mask = CGRect(x: 40.1, y: 60, width: 99.8, height: 80)
            let masked = try #require(RRWireframe.maskImage(image, maskableWidgets: [mask], pixelScale: 3)?.cgImage)
            let row = CGFloat(300)
            #expect(try isBlack(rgb(masked, at: CGPoint(x: 120, y: row))))
            #expect(try isBlack(rgb(masked, at: CGPoint(x: 419, y: row))))
            #expect(try isRed(rgb(masked, at: CGPoint(x: 119, y: row))))
            #expect(try isRed(rgb(masked, at: CGPoint(x: 420, y: row))))
        }

        @Test("an unmasked frame already at native resolution is not redrawn")
        func nativeScaleSkipsRedraw() throws {
            let window = try window()
            defer { window.isHidden = true }
            let image = try #require(window.toImage(preferFidelityRenderer: false))
            let native = pixelScale(screenshotScale: 1, on: window)
            #expect(RRWireframe.unmaskedScreenshot(image, pixelScale: native) === image)
            #expect(RRWireframe.unmaskedScreenshot(image, pixelScale: 1) !== image)
        }

        @Test("downsampling keeps a one-pixel line whichever source pixel it falls on")
        func downsamplingKeepsThinLines() throws {
            let size = CGSize(width: 30, height: 30)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            // One-pixel lines at 3x, one in each phase of the 3:1 downsample: nearest-neighbour keeps only one.
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.black.setFill()
                for (column, phase) in [(10, 0), (11, 1), (12, 2)] {
                    context.fill(CGRect(x: CGFloat(column * 3 + phase) / 3, y: 0, width: 1.0 / 3, height: size.height))
                }
            }
            let downsampled = try #require(RRWireframe.unmaskedScreenshot(image, pixelScale: 1).cgImage)
            for column in 10 ... 12 {
                let pixel = try rgb(downsampled, at: CGPoint(x: column, y: 15))
                #expect(!isWhite(pixel), "column \(column) lost its line: \(pixel)")
            }
        }

        @Test("no pixel of a resized masked frame shows any of the secret", arguments: [1.0, 1.5], [0.0, 1.0 / 3, 2.0 / 3])
        func maskedSecretDoesNotBleed(pixelScale: CGFloat, offset: CGFloat) throws {
            let size = CGSize(width: 200, height: 300)
            let secret = Self.secretRect.offsetBy(dx: offset, dy: offset)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.red.setFill()
                context.fill(secret)
            }
            let masked = try #require(RRWireframe.maskImage(image, maskableWidgets: [secret], pixelScale: pixelScale)?.cgImage)
            var rgba = [UInt8](repeating: 0, count: masked.width * masked.height * 4)
            let context = try #require(CGContext(
                data: &rgba, width: masked.width, height: masked.height, bitsPerComponent: 8, bytesPerRow: masked.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(masked, in: CGRect(x: 0, y: 0, width: masked.width, height: masked.height))
            // Black and white keep every channel equal; only the secret adds red.
            let tinted = stride(from: 0, to: rgba.count, by: 4).filter { Int(rgba[$0]) - Int(max(rgba[$0 + 1], rgba[$0 + 2])) > 2 }
            #expect(tinted.isEmpty, "\(tinted.count) pixels show the secret")
        }
    }
#endif
