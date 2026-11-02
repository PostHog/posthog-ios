#if os(iOS)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    /// An app layer with a correct `init(layer:)`, like Lottie's. It lives in the app's image, so the SDK still
    /// won't copy its presentation.
    final class AppAnimatableLayer: CALayer {
        @objc var progress: CGFloat = 0

        override init() {
            super.init()
        }

        override init(layer: Any) {
            super.init(layer: layer)
            progress = (layer as? AppAnimatableLayer)?.progress ?? 0
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
    }

    final class AppLayerView: UIView {
        override class var layerClass: AnyClass { AppAnimatableLayer.self }
    }

    /// An app layer with its own designated `init()` and no `init(layer:)`: Core Animation copying it for its
    /// presentation traps.
    final class TrappingLayer: CALayer {
        var tag: Int

        override init() {
            tag = 1
            super.init()
        }

        required init?(coder: NSCoder) {
            tag = 1
            super.init(coder: coder)
        }
    }

    final class TrappingImageView: UIImageView {
        override class var layerClass: AnyClass { TrappingLayer.self }
    }

    final class TrappingView: UIView {
        override class var layerClass: AnyClass { TrappingLayer.self }
    }

    struct RGBA: Equatable {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

        var isMagenta: Bool {
            red > 200 && green < 60 && blue > 200
        }
    }

    /// RGBA8 pixels, 1x.
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
    }

    /// A window shown without becoming key, so the SDK's own capture loop never picks it up.
    @MainActor
    func makeReplayTestWindow(frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 300)) -> UIWindow {
        let window = UIWindow(frame: frame)
        window.backgroundColor = .white
        window.isHidden = false
        return window
    }

    /// A `ph-no-capture` view filled with `color`.
    @MainActor
    func noCaptureView(_ frame: CGRect, color: UIColor = .magenta) -> UIView {
        let view = UIView(frame: frame)
        view.backgroundColor = color
        view.accessibilityIdentifier = "ph-no-capture"
        return view
    }

    /// A clear `ph-no-capture` field with magenta inset in it, as text sits in a text field: masks are drawn with
    /// rounded corners, so a fully magenta field would show at the corners.
    @MainActor
    func secretField(_ frame: CGRect, inset: CGFloat = 5) -> UIView {
        let field = noCaptureView(frame, color: .clear)
        let secret = UIView(frame: field.bounds.insetBy(dx: inset, dy: inset))
        secret.backgroundColor = .magenta
        field.addSubview(secret)
        return field
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

    /// Moves `layer` down by `distance` over a long linear animation, so its presentation stays near the start while
    /// the model already sits at the end. `checksPresentation` false for a layer whose presentation can't be copied.
    @MainActor
    func animateDown(_ layer: CALayer, by distance: CGFloat, checksPresentation: Bool = true) async throws {
        let start = layer.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position.y += distance
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(cgPoint: start)
        animation.toValue = NSValue(cgPoint: layer.position)
        animation.duration = 1000
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: "position")
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 50_000_000)
        guard checksPresentation else { return }
        let presented = try #require(layer.presentation()?.position)
        #expect(abs(presented.y - start.y) < 1)
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
