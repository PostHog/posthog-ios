#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    struct RGBA: Equatable {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

        static let magenta = RGBA(red: 255, green: 0, blue: 255, alpha: 255)
        static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
        static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
        static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
        static let green = RGBA(red: 0, green: 255, blue: 0, alpha: 255)
    }

    /// RGBA8 pixels.
    struct Pixels {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.bytes = bytes
        }

        init(_ image: UIImage) throws {
            try self.init(#require(image.cgImage))
        }

        subscript(x: Int, y: Int) -> RGBA {
            let index = (y * width + x) * 4
            return RGBA(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
        }

        func points(where predicate: (RGBA) -> Bool) -> [CGPoint] {
            var points: [CGPoint] = []
            for y in 0 ..< height {
                for x in 0 ..< width where predicate(self[x, y]) {
                    points.append(CGPoint(x: x, y: y))
                }
            }
            return points
        }

        func count(in rect: CGRect? = nil, where predicate: (RGBA) -> Bool) -> Int {
            let area = (rect ?? CGRect(x: 0, y: 0, width: width, height: height)).intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !area.isNull else { return 0 }
            var count = 0
            for y in Int(area.minY) ..< Int(area.maxY) {
                for x in Int(area.minX) ..< Int(area.maxX) where predicate(self[x, y]) {
                    count += 1
                }
            }
            return count
        }

        func maxNeighbourStep(in rect: CGRect) -> Int {
            var step = 0
            for y in Int(rect.minY) ..< Int(rect.maxY) - 1 {
                for x in Int(rect.minX) ..< Int(rect.maxX) - 1 {
                    let pixel = self[x, y], right = self[x + 1, y], below = self[x, y + 1]
                    for (a, b) in [(pixel.red, right.red), (pixel.green, right.green), (pixel.blue, right.blue),
                                   (pixel.red, below.red), (pixel.green, below.green), (pixel.blue, below.blue)]
                    {
                        step = max(step, abs(Int(a) - Int(b)))
                    }
                }
            }
            return step
        }
    }

    /// Fixtures shared by the GPU capture suites.
    @MainActor
    protocol GPUCaptureTesting {}

    extension GPUCaptureTesting {
        static func isMagenta(_ pixel: RGBA) -> Bool {
            pixel.red > 200 && pixel.green < 60 && pixel.blue > 200
        }

        func makeMirror() throws -> PostHogGPUMirrorCapture {
            // Its own instance per test, so no renderer or frame carries over between tests.
            try #require(PostHogGPUMirrorCapture(), "the simulator has no Metal device")
        }

        func makeWindow(frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 300), background: UIColor = .white) -> UIWindow {
            let window = UIWindow(frame: frame)
            window.backgroundColor = background
            // Shown without becoming key, so the SDK's own capture loop never picks it up.
            window.isHidden = false
            return window
        }

        func prewarm(_ mirror: PostHogGPUMirrorCapture, for window: UIWindow, scale: CGFloat = 1) async {
            await withCheckedContinuation { continuation in
                mirror.prewarm(size: window.bounds.size, scale: scale) { continuation.resume() }
            }
        }

        func noCaptureView(_ frame: CGRect, color: UIColor = .magenta) -> UIView {
            let view = UIView(frame: frame)
            view.backgroundColor = color
            view.accessibilityIdentifier = "ph-no-capture"
            return view
        }

        /// Magenta layer contents: drawn content, which a mask has to remove, unlike a background colour.
        func magentaContents(_ size: CGSize) throws -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try #require(UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.magenta.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }.cgImage)
        }
    }
#endif
