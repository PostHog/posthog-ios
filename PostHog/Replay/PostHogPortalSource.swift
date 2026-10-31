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
        /// position and transform, are drawn: what the others show can't be placed with certainty. `root` is the
        /// window's layer.
        static func placement(of portal: CALayer, source: CALayer, root: CALayer) -> Placement? {
            guard isWindowContext(portal, root: root), let superlayer = source.superlayer else { return nil }
            switch (portal.value(forKey: "matchesPosition") as? Bool, portal.value(forKey: "matchesTransform") as? Bool) {
            case (true, true):
                return inPlaceTransform(from: superlayer, to: portal).map(Placement.inPlace)
            case (false, false):
                return .atPortal
            default:
                return nil
            }
        }

        /// Measured on the presentation tree, as the mirror draws the source's subtree and the mask rects are measured.
        /// When one of the layers can't be asked for its presentation copy, the model layers are used unless one is
        /// animating: then where the source is drawn isn't known and the portal is left out.
        private static func inPlaceTransform(from superlayer: CALayer, to portal: CALayer) -> CGAffineTransform? {
            let layers = [superlayer, portal]
            guard layers.allSatisfy({ PostHogGPUMirrorCapture.isPresentationSafe(type(of: $0)) }) else {
                return layers.contains { $0.animationKeys() != nil } ? nil : affineTransform(from: superlayer, to: portal)
            }
            return affineTransform(from: superlayer.presentation() ?? superlayer, to: portal.presentation() ?? portal)
        }

        /// An `.atPortal` portal's bounds in window coordinates, for the mask walk. `root` is the window's layer.
        /// Measured on the presentation tree, as the mirror draws it and the mask rects are measured (mid-animation the
        /// model layers already sit at the destination), unless one of the layers can't be asked for its presentation copy.
        static func portalRect(of portal: CALayer, root: CALayer) -> CGRect {
            let presented = [portal, root].allSatisfy { PostHogGPUMirrorCapture.isPresentationSafe(type(of: $0)) }
            let portal = presented ? portal.presentation() ?? portal : portal
            let root = presented ? root.presentation() ?? root : root
            return root.convert(portal.bounds, from: portal)
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

        /// Maps `source`'s bounds coordinates to `target`'s; nil when that isn't finite.
        static func affineTransform(from source: CALayer, to target: CALayer) -> CGAffineTransform? {
            affineTransform { target.convert($0, from: source) }
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
