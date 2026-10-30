// Portions of this file are derived from getsentry/sentry-cocoa
// Copyright (c) 2015 Sentry
// Licensed under the MIT License: https://github.com/getsentry/sentry-cocoa/blob/main/LICENSE.md

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
        private let roundingUp: Bool

        /// `roundingUp` rounds the pixel size up instead of down, and stretches `size` over every pixel so none
        /// is left undrawn.
        init(size: CGSize, scale: CGFloat, roundingUp: Bool = false) {
            self.size = size
            self.scale = scale
            self.roundingUp = roundingUp
        }

        private func pixels(_ points: CGFloat) -> Int {
            // The tolerance keeps float error, such as 100 × 0.30000000000000004, from adding a pixel.
            roundingUp ? Int((points * scale - 0.001).rounded(.up)) : Int(points * scale)
        }

        func image(actions: (CGContext) -> Void) -> UIImage? {
            let pixelsPerRow = pixels(size.width)
            let pixelsPerColumn = pixels(size.height)
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * pixelsPerRow
            let bitsPerComponent = 8

            guard pixelsPerRow > 0, pixelsPerColumn > 0 else {
                return nil
            }

            let bufferSize = pixelsPerColumn * bytesPerRow
            // calloc, not malloc: pixels the draw leaves uncovered must be transparent, not stale heap bytes.
            guard let rawData = calloc(bufferSize, 1) else {
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
            let scaleX = roundingUp ? CGFloat(pixelsPerRow) / size.width : scale
            let scaleY = roundingUp ? CGFloat(pixelsPerColumn) / size.height : scale
            context.translateBy(x: 0, y: size.height * scaleY)
            context.scaleBy(x: scaleX, y: -scaleY)

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
