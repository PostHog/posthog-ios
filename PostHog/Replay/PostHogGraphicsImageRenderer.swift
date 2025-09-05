//
//  PostHogGraphicsImageRenderer.swift
//  PostHog
//
//  Created by Ioannis Josephides on 05/09/2025.
//

#if os(iOS)
import UIKit

/**
 * High-performance image renderer optimized for PostHog session replay capture.
 *
 * This class bypasses UIKit's UIGraphicsImageRenderer to work directly with CoreGraphics,
 * eliminating overhead from internal caching mechanisms and providing significant performance
 * improvements for frequent screenshot capture operations.
 *
 * Inspired by Sentry's SentryGraphicsImageRenderer implementation which achieved ~80%
 * performance improvement over UIGraphicsImageRenderer.
 */
final class PostHogGraphicsImageRenderer {
    
    struct Context {
        let cgContext: CGContext
        let scale: CGFloat
        
        /// Converts the current context into an image.
        ///
        /// - Returns: The image representation of the current context, or empty image on failure.
        var currentImage: UIImage {
            guard let cgImage = cgContext.makeImage() else {
                hedgeLog("PostHogGraphicsImageRenderer: Unable to create image from graphics context")
                return UIImage()
            }
            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }
    }
    
    let size: CGSize
    let scale: CGFloat
    
    init(size: CGSize, scale: CGFloat) {
        self.size = size
        self.scale = scale
    }
    
    /// Creates an image by executing the provided drawing actions in a CoreGraphics context.
    ///
    /// - Parameter actions: Drawing operations to perform in the context
    /// - Returns: The resulting UIImage, or empty image on failure
    func image(actions: (Context) -> Void) -> UIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let pixelsPerRow = Int(size.width * scale)
        let pixelsPerColumn = Int(size.height * scale)
        let bytesPerPixel = 4 // 4 bytes for RGBA
        let bytesPerRow = bytesPerPixel * pixelsPerRow
        let bitsPerComponent = 8 // 8 bits for each RGB component
        
        // Allocate memory for raw image data and initialize to zero
        guard let rawData = calloc(pixelsPerColumn * bytesPerRow, MemoryLayout<UInt8>.size) else {
            hedgeLog("PostHogGraphicsImageRenderer: Unable to allocate memory for image data")
            return UIImage()
        }
        defer {
            free(rawData) // Release memory when done
        }
        
        guard let context = CGContext(
            data: rawData,
            width: pixelsPerRow,
            height: pixelsPerColumn,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            hedgeLog("PostHogGraphicsImageRenderer: Unable to create CoreGraphics context")
            return UIImage()
        }
        
        // Handle coordinate system mismatch between UIKit and CoreGraphics
        // UIKit has origin at top-left, CoreGraphics has origin at bottom-left
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -1 * scale)
        
        // Push context to make it the current graphics context for UIKit drawing operations
        UIGraphicsPushContext(context)
        let rendererContext = Context(cgContext: context, scale: scale)
        actions(rendererContext)
        UIGraphicsPopContext()
        
        return rendererContext.currentImage
    }
}
#endif
