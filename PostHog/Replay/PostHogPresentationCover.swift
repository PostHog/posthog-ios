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
                isOpaqueCover(controller, view),
                // Also settles that the view is in this window: the walk ends there.
                isTopmost(view, in: window),
                // Presentation geometry, so a cover still animating in does not qualify.
                view.toPresentationRect(window).contains(window.bounds)
            else {
                return nil
            }
            return view
        }

        /// Whether the cover is the last thing drawn in the window. A view added to the window
        /// after the presentation container — an app's own banner, for one — draws over the
        /// cover and still shows, so its content has to stay masked.
        private static func isTopmost(_ view: UIView, in window: UIWindow) -> Bool {
            var current = view
            while let parent = current.superview {
                guard parent.subviews.last === current else { return false }
                if parent === window { return true }
                current = parent
            }
            return false
        }

        /// `.fullScreen` is opaque by UIKit's own contract: it is the style for which UIKit may
        /// drop the presenter's view from the window. Every other style keeps the presenter
        /// visible unless the presented view paints an opaque background over its whole extent.
        /// `UIView.isOpaque` is no help here — it is a drawing hint that defaults to true even
        /// on a see-through view, and trusting it would unmask content that still shows.
        private static func isOpaqueCover(_ controller: UIViewController, _ view: UIView) -> Bool {
            guard !view.isHidden, view.alpha >= 1 else {
                return false
            }
            if controller.modalPresentationStyle == .fullScreen {
                return true
            }
            // Inferring cover from what the view paints has to account for the shape it paints
            // in: a background colour only fills the layer's own outline. Rounded corners leave
            // the presenter showing through the corner arcs, and a mask layer can cut any hole
            // it likes. `toPresentationRect` reports the plain bounds either way, so the
            // full-window test sees neither.
            guard view.layer.cornerRadius == 0, view.layer.mask == nil else {
                return false
            }
            return (view.backgroundColor?.cgColor.alpha ?? 0) >= 1
        }
    }
#endif
