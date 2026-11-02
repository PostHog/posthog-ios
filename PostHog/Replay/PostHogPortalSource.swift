#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    /// A view whose layer a GPU-captured frame also draws through a portal (`CAPortalLayer`), and where.
    ///
    /// The mask walk measures views where they sit. A portal that shows its source in place puts its pixels there
    /// too; one that shows it at its own position (SwiftUI's Liquid Glass text) puts them where the portal is, so the
    /// whole portal is masked unless the source is shown to be clean.
    struct PostHogPortalSource {
        let view: UIView
        let portal: CALayer
        /// The portal's bounds in window coordinates, set when the portal shows the source somewhere other than where
        /// it sits.
        let portalRect: CGRect?

        /// How a portal places its source's subtree, or nil for a portal the mirror leaves out.
        enum Placement {
            /// At the source's own position and transform: a transform from the source's superlayer to the portal.
            case inPlace(CGAffineTransform)
            /// With the source's bounds on the portal's bounds, its own position and transform ignored.
            case atPortal
        }

        /// Only portals from the capturing window's render context, which are both matched or both unmatched in
        /// position and transform, are drawn: what the others show can't be placed with certainty. A matched portal is
        /// also left out when its own or the source's superlayer transforms or flips its sublayers, when either's place
        /// can only be read from a moving model, or when the placement isn't affine. `root` is the window's layer.
        static func placement(of portal: CALayer, source: CALayer, root: CALayer) -> Placement? {
            guard isWindowContext(portal, root: root), let superlayer = source.superlayer else { return nil }
            switch (portal.value(forKey: "matchesPosition") as? Bool, portal.value(forKey: "matchesTransform") as? Bool) {
            case (true, true):
                // `convert` leaves out what the superlayer applies to its sublayers, which the mask rects include, and
                // what the portal applies to its own, which the portal's copy applies again.
                guard !transformsSublayers(superlayer), !transformsSublayers(portal) else { return nil }
                return inPlaceTransform(from: superlayer, to: portal).map(Placement.inPlace)
            case (false, false):
                return .atPortal
            default:
                return nil
            }
        }

        private static func transformsSublayers(_ layer: CALayer) -> Bool {
            let presented = PostHogGPUMirrorCapture.isPresentationSafe(type(of: layer)) ? layer.presentation() : nil
            return [layer, presented].compactMap { $0 }.contains { !CATransform3DIsIdentity($0.sublayerTransform) || $0.isGeometryFlipped }
        }

        /// Measured where each layer is presented, as the mirror draws the source's subtree and the mask rects are
        /// measured. Nil when that place is read from a moving model (see `CALayer.presentationAnchor`).
        private static func inPlaceTransform(from superlayer: CALayer, to portal: CALayer) -> CGAffineTransform? {
            guard let from = superlayer.presentationAnchor(), !from.isMoving, let to = portal.presentationAnchor(), !to.isMoving else { return nil }
            return affineTransform { point in
                portal.convert(to.presented.convert(superlayer.convert(point, to: from.layer), from: from.presented), from: to.layer)
            }
        }

        /// An `.atPortal` portal's bounds in window coordinates, for the mask walk. `root` is the window's layer.
        /// Measured on the presentation tree, as the mirror draws it and the mask rects are measured (mid-animation the
        /// model layers already sit at the destination).
        static func portalRect(of portal: CALayer, root: CALayer) -> CGRect {
            portal.presentedRect(in: root).rect
        }

        /// UIKit leaves the source context unset (0); SwiftUI sets it to the window's own. Unreadable means skipped.
        private static func isWindowContext(_ portal: CALayer, root: CALayer) -> Bool {
            guard let contextID = (portal.value(forKey: "sourceContextId") as? NSNumber)?.uint32Value else { return false }
            if contextID == 0 { return true }
            guard let context = root.value(forKey: "context") as? NSObject,
                  context.responds(to: NSSelectorFromString("contextId")),
                  let windowContextID = (context.value(forKey: "contextId") as? NSNumber)?.uint32Value
            else { return false }
            return contextID == windowContextID
        }

        /// The affine transform `apply` performs, sampled at three points; nil when it isn't finite or a fourth point
        /// shows it isn't affine (a 3D transform on the way).
        private static func affineTransform(_ apply: (CGPoint) -> CGPoint) -> CGAffineTransform? {
            let origin = apply(.zero)
            let unitX = apply(CGPoint(x: 100, y: 0))
            let unitY = apply(CGPoint(x: 0, y: 100))
            let transform = CGAffineTransform(a: (unitX.x - origin.x) / 100, b: (unitX.y - origin.y) / 100,
                                              c: (unitY.x - origin.x) / 100, d: (unitY.y - origin.y) / 100, tx: origin.x, ty: origin.y)
            let values = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
            guard values.allSatisfy(\.isFinite) else { return nil }
            let check = CGPoint(x: 100, y: 100)
            let expected = check.applying(transform), actual = apply(check)
            return abs(expected.x - actual.x) < 0.01 && abs(expected.y - actual.y) < 0.01 ? transform : nil
        }
    }
#endif
