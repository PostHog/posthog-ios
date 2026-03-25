#if os(iOS)

    import UIKit

    /// Cached device RGB color space — avoids creating a new one per render call.
    private let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    /// High-performance image renderer that bypasses `UIGraphicsImageRenderer`'s overhead.
    ///
    /// Based on Sentry's approach: directly allocates a `CGContext` with `malloc`, avoiding
    /// UIKit's internal caching and context management abstractions.
    ///
    /// See: https://blog.sentry.io/boosting-session-replay-performance-on-ios-with-view-renderer-v2/

    final class PostHogGraphicsImageRenderer {
        let size: CGSize
        let scale: CGFloat

        init(size: CGSize, scale: CGFloat) {
            self.size = size
            self.scale = scale
        }

        func image(actions: (CGContext) -> Void) -> UIImage? {
            let pixelsPerRow = Int(size.width * scale)
            let pixelsPerColumn = Int(size.height * scale)
            let bytesPerPixel = 4 // RGBA
            let bytesPerRow = bytesPerPixel * pixelsPerRow
            let bitsPerComponent = 8

            guard pixelsPerRow > 0, pixelsPerColumn > 0 else {
                return nil
            }

            // Allocate memory for raw image data.
            // Using malloc instead of calloc — drawHierarchy overwrites the entire buffer,
            // so zero-initialization is unnecessary and wastes time for large buffers.
            let bufferSize = pixelsPerColumn * bytesPerRow
            guard let rawData = malloc(bufferSize) else {
                return nil
            }
            defer {
                free(rawData)
            }

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

            // UIKit coordinate system is flipped vs CoreGraphics — shift and scale to match
            context.translateBy(x: 0, y: size.height * scale)
            context.scaleBy(x: scale, y: -1 * scale)

            // Push context so drawHierarchy draws into our context
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
