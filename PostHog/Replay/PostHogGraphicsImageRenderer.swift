#if os(iOS)

    import UIKit

    /// Cached device RGB color space — avoids creating a new one per render call.
    private let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    /// High-performance image renderer that bypasses `UIGraphicsImageRenderer` overhead.
    ///
    /// This directly allocates a `CGContext` for the target image and pushes it as the
    /// current UIKit context, allowing existing UIKit drawing APIs such as
    /// `drawHierarchy(in:afterScreenUpdates:)` and `UIImage.draw(at:)` to render into it.
    final class PostHogGraphicsImageRenderer {
        private let size: CGSize
        private let scale: CGFloat

        init(size: CGSize, scale: CGFloat) {
            self.size = size
            self.scale = scale
        }

        func image(actions: (CGContext) -> Void) -> UIImage? {
            let pixelsPerRow = Int(size.width * scale)
            let pixelsPerColumn = Int(size.height * scale)
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * pixelsPerRow
            let bitsPerComponent = 8

            guard pixelsPerRow > 0, pixelsPerColumn > 0 else {
                return nil
            }

            let bufferSize = pixelsPerColumn * bytesPerRow
            guard let rawData = malloc(bufferSize) else {
                return nil
            }
            defer { free(rawData) }

            guard let context = CGContext(
                data: rawData,
                width: pixelsPerRow,
                height: pixelsPerColumn,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: deviceRGBColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }

            // UIKit's coordinate system is flipped relative to CoreGraphics.
            context.translateBy(x: 0, y: size.height * scale)
            context.scaleBy(x: scale, y: -scale)

            UIGraphicsPushContext(context)
            actions(context)
            UIGraphicsPopContext()

            guard let cgImage = context.makeImage() else {
                return nil
            }
            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }
    }

#endif
