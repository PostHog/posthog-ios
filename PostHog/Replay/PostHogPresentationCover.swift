//
//  PostHogPresentationCover.swift
//  PostHog
//

#if os(iOS)
    import Foundation
    import UIKit

    /// A presented view controller can hide everything behind it while that content stays
    /// attached to the window — SwiftUI's `fullScreenCover` does this on newer OS versions,
    /// where UIKit no longer takes the presenter's view out of the hierarchy. Redaction rects
    /// collected from the covered content would then be painted over the cover's own pixels,
    /// so the capture path asks here which view, if any, holds the whole window.
    enum PostHogPresentationCover {
        /// The frontmost presented view that covers `window` completely and opaquely, or nil
        /// when content behind the presentation still shows. Only a cover that spans the whole
        /// window qualifies, so a sheet, a partial cover, or a transition still on its way in
        /// keeps everything behind it masked — the check fails closed.
        static func frontmostFullWindowCover(in window: UIWindow) -> UIView? {
            var cover: UIView?
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController {
                // A deeper presentation sits in front, so it wins over the one before it.
                cover = fullWindowCoverView(presented, in: window) ?? cover
                controller = presented
            }
            return cover
        }

        private static func fullWindowCoverView(_ controller: UIViewController, in window: UIWindow) -> UIView? {
            guard
                let view = controller.viewIfLoaded,
                isOpaqueCover(view),
                hasUnobstructedCoverage(view, in: window),
                view.convert(view.bounds, to: window).contains(window.bounds),
                view.toPresentationRect(window).contains(window.bounds)
            else {
                return nil
            }
            return view
        }

        private static func hasUnobstructedCoverage(_ view: UIView, in window: UIWindow) -> Bool {
            var current = view
            while true {
                let layer = current.layer
                guard isUnmodifiedRectangle(layer, in: window.layer),
                      isUnmodifiedRectangle(layer.presentation() ?? layer, in: window.layer.presentation() ?? window.layer)
                else {
                    return false
                }
                if current === window { return true }
                guard let parent = current.superview, drawsLast(current, in: parent) else { return false }
                current = parent
            }
        }

        // Check both trees: destination values can already be opaque/rectangular while the
        // rendered cover still exposes the presenter. Unknown shapes keep the masks behind them.
        private static func isUnmodifiedRectangle(_ layer: CALayer, in windowLayer: CALayer) -> Bool {
            guard !layer.isHidden, layer.opacity >= 1,
                  layer.cornerRadius == 0, layer.mask == nil,
                  CATransform3DIsAffine(layer.transform),
                  CATransform3DIsIdentity(layer.sublayerTransform)
            else {
                return false
            }
            let transform = CATransform3DGetAffineTransform(layer.transform)
            guard transform.a > 0, transform.d > 0, transform.b == 0, transform.c == 0 else {
                return false
            }
            return !layer.masksToBounds || layer.convert(layer.bounds, to: windowLayer).contains(windowLayer.bounds)
        }

        /// Whether `view` is the last of its siblings to be drawn. Subview order alone does not
        /// settle that: sibling layers composite by `zPosition` and fall back to that order only
        /// when the values tie. Raising `zPosition` is how an app keeps a banner above the
        /// presentations made after it — the very case the caller exists to catch — so a sibling
        /// sitting earlier in the array still wins when its `zPosition` is higher.
        private static func drawsLast(_ view: UIView, in parent: UIView) -> Bool {
            var isAfterView = false
            for sibling in parent.subviews {
                if sibling === view {
                    isAfterView = true
                    continue
                }
                let layer = sibling.layer
                if layer.isHidden || layer.opacity <= 0 {
                    // A fading sibling can still draw even after its model opacity reaches zero.
                    let rendered = layer.presentation() ?? layer
                    if rendered.isHidden || rendered.opacity <= 0 {
                        continue
                    }
                }
                let position = layer.zPosition
                if position > view.layer.zPosition || (position == view.layer.zPosition && isAfterView) {
                    return false
                }
            }
            // False also when `view` is no subview of `parent`, which no caller should reach.
            return isAfterView
        }

        private static func isOpaqueCover(_ view: UIView) -> Bool {
            let layer = view.layer
            // Presentation style and isOpaque are not proof of the pixels currently painted.
            return (layer.backgroundColor?.alpha ?? 0) >= 1 &&
                ((layer.presentation() ?? layer).backgroundColor?.alpha ?? 0) >= 1
        }
    }
#endif
