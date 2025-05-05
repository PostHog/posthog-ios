//
//  PostHogViewRenderer.swift
//  PostHog
//
//  Created by Ioannis Josephides on 05/05/2025.
//

#if os(iOS)
    import UIKit

    enum PostHogViewRenderer {
        // Cache renderers by size for reuse
        private static let rendererCache: NSCache<NSValue, UIGraphicsImageRenderer> = {
            let cache = NSCache<NSValue, UIGraphicsImageRenderer>()
            // Typical max number of different window sizes. NSCache will automatically evict least recently used items when capacity is exceeded
            cache.countLimit = 5
            return cache
        }()

        // Static format optimized for window capture
        private static let format: UIGraphicsImageRendererFormat = {
            let format = UIGraphicsImageRendererFormat.default()
            format.preferredRange = .standard
            /// Capture at scale 1 to ensure the image is not upscaled on retina displays.
            format.scale = 1
            format.opaque = true
            return format
        }()

        private static func cachedRenderer(for size: CGSize) -> UIGraphicsImageRenderer {
            let sizeKey = NSValue(cgSize: size)
            if let cached = rendererCache.object(forKey: sizeKey) {
                return cached
            }
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            rendererCache.setObject(renderer, forKey: sizeKey)
            return renderer
        }

        static func capture(_ view: UIView, scale: CGFloat) -> UIImage? {
            // Skip invisible views early
            guard !view.isHidden, view.alpha > 0 else { return nil }

            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            // Capture at the specified scale for performance
            let captureSize = CGSize(
                width: bounds.width * scale,
                height: bounds.height * scale
            )

            // Capture at low resolution
            return cachedRenderer(for: captureSize).image { context in
                context.cgContext.scaleBy(x: scale, y: scale)
                view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
        }
    }
#endif
