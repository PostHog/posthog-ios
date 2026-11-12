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
        /// False when the mirror draws the source only through portals: hidden by one walked first, or culled where it
        /// sits. An overlay beside it then has no copy of it to mask in place.
        var hasInPlaceCopy = true

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

    /// Where a layer's presented place can be read from (see `CALayer.presentationAnchor`).
    struct PostHogPresentationAnchor {
        /// The nearest layer at or above the measured one that the presentation tree can be read through.
        let layer: CALayer
        let presented: CALayer
        /// Whether a layer between the measured one and `layer` has a geometric animation, so the model that places
        /// the measured layer under `layer` can sit away from what's shown.
        let isMoving: Bool
    }

    extension CALayer {
        /// This layer's presented bounds in `windowLayer`'s space, read without copying a presentation `isPresentationSafe`
        /// rejects, and whether the rect is exact. It isn't while a layer on the way to the presentation anchor can't be
        /// read (see `presentedGeometry`): the rect then spans the window.
        func presentedRect(in windowLayer: CALayer?, outsets: UIEdgeInsets = .zero) -> (rect: CGRect, isExact: Bool) {
            guard let anchor = presentationAnchor() else { return (convert(bounds.outset(by: outsets), to: windowLayer), true) }
            let presentedWindow = windowLayer.map { $0.presentationAnchor()?.presented ?? $0 }
            if let placed = presentedRect(under: anchor.layer, outsets: outsets) {
                return (anchor.presented.convert(placed, to: presentedWindow), true)
            }
            let model = anchor.presented.convert(convert(bounds.outset(by: outsets), to: anchor.layer), to: presentedWindow)
            return (model.union((presentedWindow ?? rootLayer).bounds), false)
        }

        /// This layer's presented bounds grown by `outsets`, in `ancestor`'s space. Composed from each layer's own
        /// presented geometry on the way, as Core Animation places a sublayer, since converting through a presentation
        /// copy copies the ancestors whose class can't be. nil when a layer on the way can't be read, a transform layer
        /// keeps its sublayers in 3D, or a corner lands behind the eye.
        private func presentedRect(under ancestor: CALayer, outsets: UIEdgeInsets) -> CGRect? {
            guard var geometry = presentedGeometry else { return nil }
            var rect: CGRect? = geometry.bounds.outset(by: outsets)
            var pending = CATransform3DIdentity
            var layer = self
            while layer !== ancestor {
                guard let superlayer = layer.superlayer, !(superlayer is CATransformLayer), let parent = superlayer.presentedGeometry else {
                    return nil
                }
                let step = geometry.transform(toSuperlayer: parent)
                pending = CATransform3DConcat(pending, step)
                // Core Animation bounds the rect wherever perspective applies, rather than once at the end.
                if step.m14 != 0 || step.m24 != 0 || step.m44 != 1 {
                    rect = rect?.projected(by: pending)
                    pending = CATransform3DIdentity
                }
                layer = superlayer
                geometry = parent
            }
            return rect?.projected(by: pending)
        }

        /// This layer's own geometry as presented: its presentation copy, or the model while it has none (not committed
        /// yet) or its class can't be copied and nothing moves it. nil when its class can't be copied and an animation
        /// can move it. Not for converting or reading `superlayer`.
        var presentedGeometry: CALayer? {
            guard PostHogGPUMirrorCapture.isPresentationSafe(type(of: self)) else { return hasGeometricAnimation ? nil : self }
            return presentation() ?? self
        }

        /// Maps this layer's space into `superlayer`'s, both read as given, flattened onto `superlayer`'s plane.
        /// `CATransform3D` maps row vectors, so each step concatenates on the right.
        private func transform(toSuperlayer superlayer: CALayer) -> CATransform3D {
            var transform = CATransform3DIdentity
            if isGeometryFlipped {
                transform = CATransform3DTranslate(CATransform3DMakeScale(1, -1, 1), 0, -(bounds.minY + bounds.maxY), 0)
            }
            let anchor = bounds.point(at: anchorPoint)
            transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(-anchor.x, -anchor.y, -anchorPointZ))
            transform = CATransform3DConcat(transform, self.transform)
            transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(position.x, position.y, zPosition))
            let parentAnchor = superlayer.bounds.point(at: superlayer.anchorPoint)
            let toParentAnchor = CATransform3DMakeTranslation(parentAnchor.x, parentAnchor.y, superlayer.anchorPointZ)
            transform = CATransform3DConcat(transform, CATransform3DInvert(toParentAnchor))
            transform = CATransform3DConcat(transform, superlayer.sublayerTransform)
            transform = CATransform3DConcat(transform, toParentAnchor)
            transform.m13 = 0
            transform.m23 = 0
            transform.m33 = 0
            transform.m43 = 0
            return transform
        }

        private var rootLayer: CALayer {
            superlayer?.rootLayer ?? self
        }

        /// Where to read this layer's presented place from. Converting through a presentation copy, or reading its
        /// `superlayer`, copies every ancestor's presentation too, which traps on a class `isPresentationSafe` rejects,
        /// so the presentation tree is read only above the topmost such layer, from the nearest layer there that has
        /// a presentation (one not committed yet has none). nil when there's none.
        func presentationAnchor() -> PostHogPresentationAnchor? {
            var readableFrom: CALayer? = self
            var ancestor: CALayer? = self
            while let current = ancestor {
                if !PostHogGPUMirrorCapture.isPresentationSafe(type(of: current)) { readableFrom = current.superlayer }
                ancestor = current.superlayer
            }
            var isMoving = false
            var isReadable = false
            var current: CALayer? = self
            while let layer = current {
                if layer === readableFrom { isReadable = true }
                if isReadable, let presented = layer.presentation() {
                    return PostHogPresentationAnchor(layer: layer, presented: presented, isMoving: isMoving)
                }
                if layer.hasGeometricAnimation { isMoving = true }
                current = layer.superlayer
            }
            return nil
        }

        /// Whether an animation can move or reshape this layer: any but a property animation of its opacity or
        /// background colour. Matched by key path, since an animation can be added under any key.
        var hasGeometricAnimation: Bool {
            guard let keys = animationKeys() else { return false }
            return keys.contains { key in
                guard let animation = animation(forKey: key) as? CAPropertyAnimation, let keyPath = animation.keyPath else { return true }
                return !Self.nonGeometricKeyPaths.contains(keyPath)
            }
        }

        private static let nonGeometricKeyPaths: Set<String> = ["opacity", "backgroundColor"]
    }

    private extension CGRect {
        func point(at unit: CGPoint) -> CGPoint {
            CGPoint(x: minX + unit.x * width, y: minY + unit.y * height)
        }

        /// The bounding box of the corners `transform` maps, nil when one lands behind the eye.
        func projected(by transform: CATransform3D) -> CGRect? {
            if CATransform3DIsIdentity(transform) { return self }
            var xs: [CGFloat] = []
            var ys: [CGFloat] = []
            for corner in [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)] {
                let depth = corner.x * transform.m14 + corner.y * transform.m24 + transform.m44
                guard depth > 0 else { return nil }
                xs.append((corner.x * transform.m11 + corner.y * transform.m21 + transform.m41) / depth)
                ys.append((corner.x * transform.m12 + corner.y * transform.m22 + transform.m42) / depth)
            }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
#endif
