//
//  PostHogViewRenderer.swift
//  PostHog
//
//  Created by Ioannis Josephides on 05/09/2025.
//

#if os(iOS)
    import UIKit

    enum PostHogViewRenderer {
        private static let reuseRenderer: Bool = false
        private static let useLegacyRender: Bool = true

        private static var rendererCache: [RendererKey: CustomImageRenderer] = [:]
        private static let cacheLock = NSLock()
        private static let maxRendererCacheSize = 3

        private struct RendererKey: Hashable {
            let size: CGSize
            let scale: CGFloat

            func hash(into hasher: inout Hasher) {
                hasher.combine(size.width)
                hasher.combine(size.height)
                hasher.combine(scale)
            }
        }

        static func capture(_ view: UIView, scale: CGFloat) -> UIImage? {
            let startRenderTime = DispatchTime.now().uptimeNanoseconds

            let bounds = view.bounds

            let getRenderer: () -> CustomImageRenderer = {
                useLegacyRender ? LegacyImageRenderer(size: bounds.size, scale: scale) : ImprovedViewRenderer(size: bounds.size, scale: scale)
            }

            let key = RendererKey(size: bounds.size, scale: scale)
            let renderer = reuseRenderer ? rendererCache[key, default: getRenderer()] : getRenderer()

            let result = renderer.toImage(view: view)

            defer {
                let endRenderTime = DispatchTime.now().uptimeNanoseconds
                printCaptureSummary(
                    renderDiff: endRenderTime - startRenderTime,
                    method: useLegacyRender ? "legacy" : "custom renderer",
                    reuseRender: reuseRenderer,
                    scale: scale
                )
            }
            return result
        }

        
        // MARK: - Performance Tracking

        private static let toImageSampleLimit = 120
        private static var toImageRenderDiffHistory = [UInt64]()

        private static func printCaptureSummary(renderDiff: UInt64, method: String, reuseRender: Bool, scale: CGFloat) {
            toImageRenderDiffHistory = (toImageRenderDiffHistory + [renderDiff]).suffix(toImageSampleLimit)

            let renderDiffHistoryMin = Self.toImageRenderDiffHistory.min() ?? 0
            let renderDiffHistoryMax = Self.toImageRenderDiffHistory.max() ?? 0
            let renderDiffHistoryAverage = Double(Self.toImageRenderDiffHistory.reduce(0, +)) / Double(max(Self.toImageRenderDiffHistory.count, 1))
            let sortedRenderDiffHistory = Self.toImageRenderDiffHistory.sorted()
            let renderDiffHistoryP50 = sortedRenderDiffHistory[Self.toImageRenderDiffHistory.count / 2]
            let renderDiffHistoryP75 = sortedRenderDiffHistory[Int(Double(Self.toImageRenderDiffHistory.count) * 0.75)]
            let renderDiffHistoryP95 = sortedRenderDiffHistory[Int(Double(Self.toImageRenderDiffHistory.count) * 0.95)]
            let renderDiffHistoryLast = Self.toImageRenderDiffHistory.last ?? 0

            func f(_ value: UInt64) -> String {
                String(format: "%8.4f ms", Double(value) / 1_000_000.0)
            }

            func f(_ value: Double) -> String {
                String(format: "%8.4f ms", Double(value) / 1_000_000.0)
            }

            let samples = String(format: "%4.i Samples", Self.toImageRenderDiffHistory.count)
            print("toImage - method:\(method), scale: \(scale), reuseRenderer: \(reuseRender)")
            print("| \(samples) | Render Time |")
            print("|--------------|-------------|")
            print("| Min          | \(f(renderDiffHistoryMin)) |")
            print("| Max          | \(f(renderDiffHistoryMax)) |")
            print("| Avg          | \(f(renderDiffHistoryAverage)) |")
            print("| p50          | \(f(renderDiffHistoryP50)) |")
            print("| p75          | \(f(renderDiffHistoryP75)) |")
            print("| p95          | \(f(renderDiffHistoryP95)) |")
            print("| Last         | \(f(renderDiffHistoryLast)) |")
        }
    }

    // MARK: - Legacy and Custom Renderer

    protocol CustomImageRenderer {
        init(size: CGSize, scale: CGFloat)
        func toImage(view: UIView) -> UIImage?
    }

    final class LegacyImageRenderer: CustomImageRenderer {
        let renderer: UIGraphicsImageRenderer
        
        init(size: CGSize, scale: CGFloat) {
            let rendererFormat = UIGraphicsImageRendererFormat.default()

            // This can significantly improve rendering performance because the renderer won't need to
            // process transparency.
            rendererFormat.opaque = true
            renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        }

        func toImage(view: UIView) -> UIImage? {
            // Skip invisible views early
            guard !view.isHidden, view.alpha > 0 else { return nil }

            // Skip zero width or height views
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            let image = renderer.image { _ in
                /// Note: Always `false` for `afterScreenUpdates` since this will cause the screen to flicker when a sensitive text field is visible on screen
                /// This can potentially affect capturing a snapshot during a screen transition but we want the lesser of the two evils here
                view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }

            return image
        }
    }

    final class ImprovedViewRenderer: CustomImageRenderer {
        let imageRenderer: PostHogGraphicsImageRenderer
        init(size: CGSize, scale: CGFloat) {
            imageRenderer = PostHogGraphicsImageRenderer(size: size, scale: scale)
        }

        func toImage(view: UIView) -> UIImage? {
            // Skip invisible views early
            guard !view.isHidden, view.alpha > 0 else { return nil }

            // Skip zero width or height views
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            return imageRenderer.image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
            }
        }
    }
#endif
