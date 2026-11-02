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
        /// A layer whose presentation can't be copied (see `CALayer.presentedValues`) is judged
        /// by its model only while nothing animates it, unless `trustingModels`: then always, for
        /// a caller that only asks which view a cover would be, not what it may leave unmasked.
        static func frontmostFullWindowCover(in window: UIWindow, trustingModels: Bool = false) -> UIView? {
            var cover: UIView?
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController {
                // A deeper presentation sits in front, so it wins over the one before it.
                cover = fullWindowCoverView(presented, in: window, trustingModels) ?? cover
                controller = presented
            }
            return cover
        }

        private static func fullWindowCoverView(_ controller: UIViewController, in window: UIWindow, _ trustsModels: Bool) -> UIView? {
            guard
                let view = controller.viewIfLoaded,
                isOpaqueCover(view, trustsModels),
                hasUnobstructedCoverage(view, in: window, trustsModels),
                view.convert(view.bounds, to: window).contains(window.bounds),
                coversWindowAsPresented(view.layer, window, trustsModels)
            else {
                return nil
            }
            return view
        }

        private static func presented(_ layer: CALayer, _ trustsModels: Bool) -> CALayer? {
            layer.presentedValues ?? (trustsModels ? layer : nil)
        }

        private static func coversWindowAsPresented(_ layer: CALayer, _ window: UIWindow, _ trustsModels: Bool) -> Bool {
            let presented = layer.presentedRect(in: window.layer)
            return (presented.isExact || trustsModels) && presented.rect.contains(window.bounds)
        }

        private static func hasUnobstructedCoverage(_ view: UIView, in window: UIWindow, _ trustsModels: Bool) -> Bool {
            var current = view
            while true {
                let layer = current.layer
                guard isUnmodifiedRectangle(layer),
                      !layer.masksToBounds || layer.convert(layer.bounds, to: window.layer).contains(window.layer.bounds),
                      let presented = presented(layer, trustsModels), isUnmodifiedRectangle(presented),
                      !presented.masksToBounds || coversWindowAsPresented(layer, window, trustsModels)
                else {
                    return false
                }
                if current === window { return true }
                guard let parent = current.superview, drawsLast(current, in: parent, trustsModels) else { return false }
                current = parent
            }
        }

        // Check both trees: destination values can already be opaque/rectangular while the
        // rendered cover still exposes the presenter. Unknown shapes keep the masks behind them.
        private static func isUnmodifiedRectangle(_ layer: CALayer) -> Bool {
            guard !layer.isHidden, layer.opacity >= 1,
                  layer.cornerRadius == 0, layer.mask == nil,
                  CATransform3DIsAffine(layer.transform),
                  CATransform3DIsIdentity(layer.sublayerTransform)
            else {
                return false
            }
            let transform = CATransform3DGetAffineTransform(layer.transform)
            return transform.a > 0 && transform.d > 0 && transform.b == 0 && transform.c == 0
        }

        /// Whether `view` is the last of its siblings to be drawn. Subview order alone does not
        /// settle that: sibling layers composite by `zPosition` and fall back to that order only
        /// when the values tie. Raising `zPosition` is how an app keeps a banner above the
        /// presentations made after it — the very case the caller exists to catch — so a sibling
        /// sitting earlier in the array still wins when its `zPosition` is higher.
        private static func drawsLast(_ view: UIView, in parent: UIView, _ trustsModels: Bool) -> Bool {
            let viewPosition = view.layer.zPosition
            guard let renderedViewPosition = presented(view.layer, trustsModels)?.zPosition else { return false }
            var isAfterView = false
            for sibling in parent.subviews {
                if sibling === view {
                    isAfterView = true
                    continue
                }
                // A sibling that paints nothing leaves the cover's own pixels on screen, so it
                // cannot obstruct it. An overlay host parked in the window between uses is
                // exactly that, and it often carries the raised `zPosition` handled below.
                if drawsNothing(sibling) {
                    continue
                }
                let position = sibling.layer.zPosition
                if position > viewPosition || (position == viewPosition && isAfterView) {
                    return false
                }
                // Model order can already hide a sibling that is still rendered above the cover.
                guard let renderedPosition = presented(sibling.layer, trustsModels)?.zPosition,
                      renderedPosition < renderedViewPosition || (renderedPosition == renderedViewPosition && !isAfterView)
                else {
                    return false
                }
            }
            // False also when `view` is no subview of `parent`, which no caller should reach.
            return isAfterView
        }

        /// Whether `view` and its subtree paint nothing at all. Both trees again, and this one
        /// decides to *drop* masks, so only a view the model and the rendered layer agree on
        /// counts: a flag parked at its destination while the render server still shows the
        /// view keeps everything behind the presentation masked.
        private static func drawsNothing(_ view: UIView) -> Bool {
            if view.isHidden, view.layer.presentedValues?.isHidden ?? false {
                return true
            }
            return !view.hasRenderedOpacity
        }

        private static func isOpaqueCover(_ view: UIView, _ trustsModels: Bool) -> Bool {
            let layer = view.layer
            // Presentation style and isOpaque are not proof of the pixels currently painted.
            return (layer.backgroundColor?.alpha ?? 0) >= 1 &&
                (presented(layer, trustsModels)?.backgroundColor?.alpha ?? 0) >= 1
        }
    }
#endif
