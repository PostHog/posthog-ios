#if os(iOS)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    struct RGBA: Equatable {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

        static let magenta = RGBA(red: 255, green: 0, blue: 255, alpha: 255)
        static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
        static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
        static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
        static let green = RGBA(red: 0, green: 255, blue: 0, alpha: 255)

        var isMagenta: Bool {
            red > 200 && green < 60 && blue > 200
        }
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

    /// A window shown without becoming key, so the SDK's own capture loop never picks it up.
    @MainActor
    func makeReplayTestWindow(frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 300)) -> UIWindow {
        let window = UIWindow(frame: frame)
        window.backgroundColor = .white
        window.isHidden = false
        return window
    }

    /// `image` with `rects` masked the way an uploaded screenshot is.
    func maskedPixels(_ image: UIImage, _ rects: [CGRect]) throws -> Pixels {
        try Pixels(#require(RRWireframe.maskImage(image, maskableWidgets: rects, pixelScale: image.scale)?.cgImage))
    }

    /// `image` shows magenta, and `rects` cover all of it.
    func expectMagentaMasked(_ image: UIImage, _ rects: [CGRect], sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(!(try Pixels(#require(image.cgImage))).points(where: \.isMagenta).isEmpty, "no magenta drawn", sourceLocation: sourceLocation)
        let unmasked = try maskedPixels(image, rects).points(where: \.isMagenta)
        #expect(unmasked.isEmpty, "\(unmasked.count) magenta pixels unmasked, mask rects \(rects)", sourceLocation: sourceLocation)
    }

    /// Holds `layer`'s `keyPath` at `value` for the whole capture, whatever the model says.
    @MainActor
    func hold(_ layer: CALayer, keyPath: String, at value: Any) async throws {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = value
        animation.toValue = value
        animation.duration = 1000
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - 1
        layer.add(animation, forKey: keyPath)
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    /// A `pixels`-sized magenta bitmap at 1x.
    func magentaImage(_ pixels: CGSize, orientation: UIImage.Orientation = .up) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: pixels, format: format).image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(origin: .zero, size: pixels))
        }
        return try UIImage(cgImage: #require(image.cgImage), scale: 1, orientation: orientation)
    }

    /// Shows `image` in an unclipped image view, commits it, then clears it in this turn: the presentation layer
    /// still holds it, and the default capture still draws it.
    @MainActor
    func clearedImageView(_ image: UIImage, frame: CGRect, contentMode: UIView.ContentMode, in window: UIWindow,
                          beforeClearing: (UIImageView) async throws -> Void = { _ in }) async throws -> UIImageView
    {
        let imageView = UIImageView(image: image)
        imageView.contentMode = contentMode
        imageView.clipsToBounds = false
        imageView.frame = frame
        window.addSubview(imageView)
        window.layoutIfNeeded()
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 50_000_000)
        try await beforeClearing(imageView)
        try #require(imageView.layer.presentation()?.contents != nil)
        imageView.image = nil
        return imageView
    }
#endif
