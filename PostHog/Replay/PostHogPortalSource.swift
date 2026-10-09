#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    /// A view whose layer a GPU-captured frame also draws through a portal (`CAPortalLayer`), and where.
    ///
    /// The mask walk measures views where they sit. A portal that shows its source in place puts its pixels there
    /// too; one that shows it at its own position (SwiftUI's Liquid Glass text) puts them where the portal is, so the
    /// masks found under the source are moved there with the same map the mirror placed the pixels with.
    struct PostHogPortalSource {
        let view: UIView
        /// Set when the portal shows the source somewhere other than where it sits.
        let elsewhere: Elsewhere?

        struct Elsewhere {
            /// Maps window points where the source sits to where the portal shows them; nil when that couldn't be
            /// computed, which masks the whole portal instead.
            let map: CGAffineTransform?
            /// The portal's bounds in window coordinates.
            let portalRect: CGRect
        }

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
                return affineTransform(from: superlayer, to: portal).map(Placement.inPlace)
            case (false, false):
                return .atPortal
            default:
                return nil
            }
        }

        /// Where an `.atPortal` portal shows `source`, for the mask walk. `root` is the window's layer.
        static func elsewhere(source: CALayer, portal: CALayer, root: CALayer) -> Elsewhere {
            let offset = CGPoint(x: portal.bounds.minX - source.bounds.minX, y: portal.bounds.minY - source.bounds.minY)
            func move(_ point: CGPoint) -> CGPoint {
                let inSource = source.convert(point, from: root)
                return root.convert(CGPoint(x: inSource.x + offset.x, y: inSource.y + offset.y), from: portal)
            }
            return Elsewhere(map: affineTransform { move($0) }, portalRect: root.convert(portal.bounds, from: portal))
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
