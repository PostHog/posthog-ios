#if os(iOS)
    import CoreGraphics
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay screenshot renderer")
    @MainActor
    struct PostHogGraphicsImageRendererTest {
        /// Default upload size; its 1.4 MB bitmap comes from the allocator's reusable pool, so an
        /// uncleared buffer carries old heap bytes.
        private static let size = CGSize(width: 402, height: 874)
        private static let scale: CGFloat = 1
        private static let bytesPerRow = Int(size.width * scale) * 4
        private static let bufferSize = Int(size.height * scale) * bytesPerRow

        private func pixelBytes(_ image: UIImage?) throws -> [UInt8] {
            let data = try #require(image?.cgImage?.dataProvider?.data)
            return [UInt8](data as Data)
        }

        /// Seeds the allocator so the next same-size allocation returns non-zero bytes.
        private func dirtyHeap() {
            guard let block = malloc(Self.bufferSize) else { return }
            memset(block, 0xAB, Self.bufferSize)
            free(block)
        }

        @Test("a draw that paints nothing is fully transparent")
        func emptyDrawIsTransparent() throws {
            dirtyHeap()
            let image = PostHogGraphicsImageRenderer(size: Self.size, scale: Self.scale).image { _ in }

            let pixels = try pixelBytes(image)
            #expect(pixels.count == Self.bufferSize)
            #expect(pixels.allSatisfy { $0 == 0 })
        }

        @Test("a partial draw leaves the undrawn pixels transparent")
        func partialDrawLeavesRestTransparent() throws {
            dirtyHeap()
            let image = PostHogGraphicsImageRenderer(size: Self.size, scale: Self.scale).image { context in
                context.setFillColor(UIColor.red.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }

            let pixels = try pixelBytes(image)
            // Top-left origin, so the red square fills the first rows.
            #expect(Array(pixels[0 ..< 4]) == [255, 0, 0, 255])
            #expect(pixels[(Self.bytesPerRow * 100)...].allSatisfy { $0 == 0 })
        }
    }

    @Suite("Replay screenshot color space", .serialized)
    @MainActor
    struct PostHogScreenshotColorSpaceTest {
        private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
        private static let deviceRGBName = CGColorSpaceCreateDeviceRGB().name
        private static let size = CGSize(width: 40, height: 40)
        private static let scale: CGFloat = 3
        private static let expected: [UInt8] = [204, 51, 51]

        private func colorSpaceName(_ image: UIImage?) -> CFString? {
            image?.cgImage?.colorSpace?.name
        }

        private func displayP3Screenshot() throws -> UIImage {
            let fill = try #require(
                CGColor(colorSpace: Self.sRGB, components: [0.8, 0.2, 0.2, 1])?
                    .converted(to: Self.displayP3, intent: .defaultIntent, options: nil)
            )
            let image = PostHogGraphicsImageRenderer(size: Self.size, scale: Self.scale, gamut: .P3).image { context in
                context.setFillColor(fill)
                context.fill(CGRect(origin: .zero, size: Self.size))
            }
            return try #require(image)
        }

        #if !SWIFT_PACKAGE || SessionReplay
        private func uploaded(_ image: UIImage, masks: [CGRect], pixelScale: CGFloat) throws -> CGImage {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = image
            wireframe.maskableWidgets = masks
            wireframe.screenshotPixelScale = pixelScale
            let base64 = try #require(wireframe.toDict()["base64"] as? String)
            let encoded = try #require(base64.split(separator: ",").last.map(String.init))
            let data = try #require(Data(base64Encoded: encoded))
            return try #require(UIImage(data: data)?.cgImage)
        }
        #endif

        private func sRGBPixel(_ image: CGImage, column: Int, row: Int) throws -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: -column, y: row - image.height + 1, width: image.width, height: image.height))
            return Array(rgba.prefix(3))
        }

        private func isExpected(_ rgb: [UInt8]) -> Bool {
            zip(rgb, Self.expected).allSatisfy { abs(Int($0) - Int($1)) <= 6 }
        }

        @Test("a wide-gamut screen renders into a Display P3 bitmap")
        func wideGamutRendersInDisplayP3() {
            let image = PostHogGraphicsImageRenderer(size: Self.size, scale: 1, gamut: .P3).image { _ in }
            #expect(colorSpaceName(image) == CGColorSpace.displayP3)
        }

        @Test("an sRGB or unknown screen renders into a device RGB bitmap")
        func otherGamutsRenderInDeviceRGB() {
            let sRGBScreen = PostHogGraphicsImageRenderer(size: Self.size, scale: 1, gamut: .SRGB).image { _ in }
            let unknownScreen = PostHogGraphicsImageRenderer(size: Self.size, scale: 1, gamut: .unspecified).image { _ in }
            let byDefault = PostHogGraphicsImageRenderer(size: Self.size, scale: 1).image { _ in }
            #expect(colorSpaceName(sRGBScreen) == Self.deviceRGBName)
            #expect(colorSpaceName(unknownScreen) == Self.deviceRGBName)
            #expect(colorSpaceName(byDefault) == Self.deviceRGBName)
        }

        @Test("drawHierarchy renders in the screen's gamut and the presentation tree in device RGB")
        func screenshotGamutFollowsTheRenderer() {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
            let subview = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            window.addSubview(subview)
            let screenGamut = window.screen.traitCollection.displayGamut

            #expect(window.screenshotGamut(drawingHierarchy: true) == screenGamut)
            #expect(subview.screenshotGamut(drawingHierarchy: true) == screenGamut)
            #expect(window.screenshotGamut(drawingHierarchy: false) == .unspecified)
            #expect(UIView(frame: window.bounds).screenshotGamut(drawingHierarchy: true) == .unspecified)
        }

        @Test("a presentation-tree screenshot stays in device RGB on any screen")
        func presentationTreeScreenshotIsDeviceRGB() throws {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
            window.rootViewController = UIViewController()
            window.rootViewController?.view.backgroundColor = .red
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            let image = try #require(window.toImage(preferFidelityRenderer: false))
            #expect(colorSpaceName(image) == Self.deviceRGBName)
        }

        #if !SWIFT_PACKAGE || SessionReplay
        @Test("a Display P3 screenshot uploads in its sRGB colors when it is resampled")
        func displayP3ScreenshotResampled() throws {
            let uploaded = try uploaded(displayP3Screenshot(), masks: [], pixelScale: 1)
            #expect(uploaded.width == Int(Self.size.width))
            #expect(isExpected(try sRGBPixel(uploaded, column: 20, row: 20)))
        }

        @Test("a Display P3 screenshot uploads in its sRGB colors at native resolution")
        func displayP3ScreenshotAtNativeResolution() throws {
            let uploaded = try uploaded(displayP3Screenshot(), masks: [], pixelScale: Self.scale)
            #expect(uploaded.width == Int(Self.size.width * Self.scale))
            #expect(isExpected(try sRGBPixel(uploaded, column: 60, row: 60)))
        }

        @Test("a masked Display P3 screenshot uploads in its sRGB colors around the mask")
        func displayP3ScreenshotMasked() throws {
            let uploaded = try uploaded(displayP3Screenshot(), masks: [CGRect(x: 0, y: 0, width: 10, height: 10)], pixelScale: 1)
            #expect(try sRGBPixel(uploaded, column: 5, row: 5).allSatisfy { $0 < 50 })
            #expect(isExpected(try sRGBPixel(uploaded, column: 30, row: 30)))
        }
        #endif
    }
#endif
