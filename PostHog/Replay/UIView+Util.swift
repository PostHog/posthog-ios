//
//  UIView+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS)
    import Foundation
    import IOSurface
    import UIKit

    extension UIView {
        func isVisible() -> Bool {
            if isHidden || alpha == 0 || frame == .zero {
                return false
            }
            return true
        }

        /// Whether this view reaches `window`'s screen. UIKit skips a hidden or fully
        /// transparent subtree, so a view under one is absent from the screenshot even though it
        /// is still attached, and a `cover` holding the whole window leaves only its own subtree
        /// on screen. One walk up the ancestry answers both, and reaching another window (or no
        /// window) answers no. `isVisible()` reads the view alone.
        func isVisibleToWindow(_ window: UIWindow, insideCover cover: UIView? = nil) -> Bool {
            var isInsideCover = cover == nil
            var view: UIView? = self
            while let current = view, current !== window {
                if current.isHidden || !current.hasRenderedOpacity {
                    return false
                }
                if current === cover {
                    isInsideCover = true
                }
                view = current.superview
            }
            return view != nil && isInsideCover
        }

        /// Whether this view and its superviews up to and including `ancestor` are all shown.
        func isVisible(upTo ancestor: UIView) -> Bool {
            var view: UIView? = self
            while let current = view {
                if current.isHidden || !current.hasRenderedOpacity {
                    return false
                }
                if current === ancestor {
                    return true
                }
                view = current.superview
            }
            return false
        }

        /// Visibility for the mask walk, stricter than `isVisible()` because anything it
        /// calls invisible is never masked while the screenshot may still draw it:
        /// - A view fading out parks its model `alpha` at 0 on the first frame of the
        ///   animation, while the presentation layer the screenshot renders is still opaque.
        /// - A zero-size view that does not clip still draws its subviews. React Native's
        ///   default `overflow: visible` produces exactly that: a 0x0 wrapper around
        ///   visible content, so its subtree still needs the walk.
        func isVisibleForMasking() -> Bool {
            if isHidden || !hasRenderedOpacity {
                return false
            }
            if frame == .zero, clipsToBounds, layer.presentedValues?.bounds.isEmpty ?? false {
                return false
            }
            return true
        }

        /// Whether the screenshot draws this view at all. During an opacity animation the
        /// model `alpha` sits at the destination while the presentation layer holds the
        /// in-flight value the screenshot renders, so a view fading out reads as opaque
        /// here. The model value comes first, so `presentation()` — which copies the layer —
        /// is only paid for on a view that is already transparent. A fade that can't be read
        /// counts as drawn.
        var hasRenderedOpacity: Bool {
            if alpha > 0 {
                return true
            }
            return (layer.presentedValues?.opacity ?? 1) > 0
        }

        var hasRunningAnimation: Bool {
            !(layer.animationKeys()?.isEmpty ?? true)
        }

        func isNoCapture() -> Bool {
            containsAccessibilityToken("ph-no-capture")
        }

        /// Whether this view (and its subviews) is explicitly marked as non-maskable, via the
        /// `.postHogNoMask()` modifier or a `ph-no-mask` token on its `accessibilityIdentifier`
        /// or `accessibilityLabel` — the carriers React Native can reach, since it cannot apply
        /// the modifier. Unlike the sibling tokens, this one reduces masking rather than adding it.
        func isNoMask() -> Bool {
            postHogNoMask || containsAccessibilityToken("ph-no-mask")
        }

        /// Whether this view is explicitly marked to be excluded from rage click detection,
        /// via the `ph-no-rageclick` token on its `accessibilityIdentifier` or `accessibilityLabel`.
        func isNoRageClick() -> Bool {
            postHogNoRageClick || containsAccessibilityToken("ph-no-rageclick")
        }

        private func containsAccessibilityToken(_ token: String) -> Bool {
            if let identifier = accessibilityIdentifier, identifier.range(of: token, options: .caseInsensitive) != nil {
                return true
            }
            // read accessibilityLabel from the parent's view to skip the RCTRecursiveAccessibilityLabel on RN which is slow and may cause an endless loop
            // see https://github.com/facebook/react-native/issues/33084
            if let label = super.accessibilityLabel, label.range(of: token, options: .caseInsensitive) != nil {
                return true
            }
            return false
        }

        /// Backing flag for the SwiftUI `.postHogNoRageClick()` modifier. Owner-set
        /// backed (see `PostHogFlagOwners`) so overlapping regions don't clear each
        /// other on teardown.
        var postHogNoRageClick: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoRageClick)
        }

        func setPostHogNoRageClick(_ enabled: Bool, owner: UIView) {
            setPostHogFlag(&AssociatedKeys.phNoRageClick, enabled: enabled, owner: owner)
        }

        func toImage(afterScreenUpdates: Bool = false, renderer screenshotRenderer: PostHogScreenshotRenderer = .fidelity) -> UIImage? {
            // Background capture also enters here; controller traversal belongs on main.
            let hasCamera = {
                (self as? UIWindow ?? self.window)?.hasCameraForReplay() ?? false
            }
            guard !(Thread.isMainThread ? hasCamera() : DispatchQueue.main.sync(execute: hasCamera)) else {
                return nil
            }

            let bounds = self.bounds
            let size = bounds.size

            if !size.hasSize() {
                return nil
            }

            // Use native screen scale for best drawHierarchy performance.
            // Using a non-native scale can trigger internal rescaling overhead.
            let nativeScale = (self as? UIWindow ?? window)?.screen.scale ?? 1
            let renderer = PostHogGraphicsImageRenderer(size: size, scale: nativeScale)

            var drawn = true
            let image = autoreleasepool {
                renderer.image { context in
                    if afterScreenUpdates {
                        /// The bridge capture passes `true`: a freshly-presented native VC renders black otherwise.
                        drawn = drawHierarchy(in: bounds, afterScreenUpdates: true)
                        return
                    }
                    switch screenshotRenderer {
                    case .fidelity:
                        drawn = drawHierarchy(in: bounds, afterScreenUpdates: false)
                    case .presentationTree:
                        (layer.presentation() ?? layer).render(in: context)
                    case .modelTree:
                        layer.render(in: context)
                    }
                }
            }
            // drawHierarchy returns false with no frame to copy (no window scene, hidden window) and leaves the bitmap blank.
            guard drawn else {
                hedgeLog("[Session Replay] Skipping snapshot: drawHierarchy produced no image data")
                return nil
            }
            return image
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ window: UIWindow?) -> CGRect {
            convert(bounds, to: window)
        }

        /// Mask geometry only. During a CA animation the model layer parks at the destination
        /// while the presentation layer holds the in-flight position the screenshot renders, so
        /// mask rects have to come from the presentation tree. Wireframe geometry is a separate
        /// consumer with no pixels to agree with and stays on `toAbsoluteRect`.
        /// `outsets` grows the rect past the bounds, for content drawn outside them.
        func toPresentationRect(_ window: UIWindow?, outsets: UIEdgeInsets = .zero) -> CGRect {
            guard window != nil || CALayer.canCopyPresentation(of: layer) && layer.presentation() != nil else {
                // UIView's own convert, not the layer's: it resolves a nil window to the view's.
                return convert(bounds.outset(by: outsets), to: window)
            }
            return layer.toPresentationRect(window, outsets: outsets)
        }

        /// How far past its bounds the view draws its own content: an image view that doesn't
        /// clip draws its image at the size its content mode gives it, and an unclipped layer
        /// shadow repeats that content at an offset.
        var drawnOutsets: UIEdgeInsets {
            var content = bounds
            if !clipsToBounds, let imageView = self as? UIImageView {
                content = imageView.drawnImageExtent.union(imageView.replacedImageExtent ?? .null)
            }
            return layer.drawnOutsets(of: content)
        }
    }

    /// How `toImage` draws a view that isn't captured after screen updates.
    enum PostHogScreenshotRenderer {
        /// `drawHierarchy`, at full fidelity (blur, video, Metal), for when the settle check measured little enough
        /// movement that the render server's last frame, which it shows, still matches the tree the masks measure.
        case fidelity
        /// `render(in:)` of the presentation tree, the source `toPresentationRect` measures, at the same instant, so
        /// masks agree with pixels mid-motion. Blur, video and Metal render flat, and filters and `layer.mask` are
        /// skipped: content that must stay hidden needs `postHogMask()`. Only for a view whose layer
        /// `canRenderPresentationTree`.
        case presentationTree
        /// `render(in:)` of the model tree, in place of the presentation tree when that can't be rendered: masks
        /// must also cover where the model places what they mask.
        case modelTree
    }

    extension UIImageView {
        /// The union of the bounds and where each image the view can draw lands, in bounds
        /// coordinates. Only fill-to-bounds content modes keep the image inside the bounds.
        var drawnImageExtent: CGRect {
            guard !keepsImageInBounds else { return bounds }
            let sources = [image, highlightedImage].compactMap { $0 } + (animationImages ?? []) + (highlightedAnimationImages ?? [])
            return sources.reduce(bounds) { $0.union(drawnRect(ofImageSized: $1.size)) }
        }

        private var keepsImageInBounds: Bool {
            [.scaleToFill, .scaleAspectFit, .redraw].contains(contentMode)
        }

        /// Where an image replaced since the last commit lands, in bounds coordinates: the presentation layer still
        /// holds it, and the default capture draws it. Measured on the presented layer, whose bounds, gravity and
        /// contents rect place it; one it draws rotated or flipped reaches arbitrarily far. Nil when nothing was
        /// replaced; contents whose size can't be read reach arbitrarily far too, and so does what a layer whose
        /// presentation can't be copied may still show, unless the content mode keeps it in bounds.
        var replacedImageExtent: CGRect? {
            #if canImport(Metal)
                guard CALayer.canCopyPresentation(of: layer) else {
                    return keepsImageInBounds ? nil : bounds.insetBy(dx: -Self.unmeasuredImageReach, dy: -Self.unmeasuredImageReach)
                }
                guard let presented = layer.presentation(), let contents = presented.contents,
                      layer.contents.map({ $0 as AnyObject !== contents as AnyObject }) ?? true
                else { return nil }
                let gravity = presented.contentsGravity
                let typeID = CFGetTypeID(contents as AnyObject)
                let extent: CGRect
                if PostHogGPUMirrorCapture.contentsTransformKey?.changedValue(in: presented) != nil
                    || typeID != CGImage.typeID && typeID != IOSurfaceGetTypeID()
                {
                    extent = presented.bounds.insetBy(dx: -Self.unmeasuredImageReach, dy: -Self.unmeasuredImageReach)
                } else if gravity == .resize || gravity == .resizeAspect {
                    return nil
                } else {
                    extent = PostHogGPUMirrorCapture.contentsExtent(presented, contents: contents, gravity: gravity, bounds: presented.bounds)
                }
                return bounds.outset(by: CALayer.outsets(of: extent, past: presented.bounds))
            #else
                return nil
            #endif
        }

        private static let unmeasuredImageReach: CGFloat = 100_000

        private func drawnRect(ofImageSized imageSize: CGSize) -> CGRect {
            var size = imageSize
            if contentMode == .scaleAspectFill, imageSize.width > 0, imageSize.height > 0 {
                let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
                size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            }

            let originX: CGFloat
            switch contentMode {
            case .left, .topLeft, .bottomLeft: originX = 0
            case .right, .topRight, .bottomRight: originX = bounds.width - size.width
            default: originX = (bounds.width - size.width) / 2
            }
            let originY: CGFloat
            switch contentMode {
            case .top, .topLeft, .topRight: originY = 0
            case .bottom, .bottomLeft, .bottomRight: originY = bounds.height - size.height
            default: originY = (bounds.height - size.height) / 2
            }
            return CGRect(x: bounds.minX + originX, y: bounds.minY + originY, width: size.width, height: size.height)
        }
    }

    extension CGRect {
        func outset(by outsets: UIEdgeInsets) -> CGRect {
            inset(by: UIEdgeInsets(top: -outsets.top, left: -outsets.left, bottom: -outsets.bottom, right: -outsets.right))
        }

        fileprivate func point(at unit: CGPoint) -> CGPoint {
            CGPoint(x: minX + unit.x * width, y: minY + unit.y * height)
        }

        /// The bounding box of the corners `transform` maps, nil when one lands behind the eye.
        fileprivate func projected(by transform: CATransform3D) -> CGRect? {
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

    extension UIWindow {
        /// CameraUI layers on iOS 26 can trap in init(layer:) when Core Animation copies
        /// them. Skip the frame before either masking or rendering reads presentation layers.
        /// Call on main; inspecting controllers does not copy the camera's layer tree.
        func hasCameraForReplay() -> Bool {
            func containsCamera(_ controller: UIViewController) -> Bool {
                if let picker = controller as? UIImagePickerController,
                   picker.sourceType == .camera,
                   picker.viewIfLoaded?.window === self
                {
                    return true
                }
                if let presented = controller.presentedViewController, containsCamera(presented) {
                    return true
                }
                return controller.children.contains(where: containsCamera)
            }
            return rootViewController.map(containsCamera) ?? false
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
        func toPresentationRect(_ window: UIWindow?, outsets: UIEdgeInsets = .zero) -> CGRect {
            presentedRect(in: window?.layer, outsets: outsets).rect
        }

        /// `toPresentationRect` in `windowLayer`'s space, and whether the rect is exact. It isn't while a layer on the
        /// way to the presentation anchor can't be read (see `presentedGeometry`): the rect then spans the window.
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
        /// can move it. Like `presentedValues`, not for converting or reading `superlayer`.
        var presentedGeometry: CALayer? {
            guard Self.canCopyPresentation(of: self) else { return hasGeometricAnimation ? nil : self }
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
        /// `superlayer`, copies every ancestor's presentation too, which traps on a class `canCopyPresentation` rejects,
        /// so the presentation tree is read only above the topmost such layer, from the nearest layer there that has
        /// a presentation (one not committed yet has none). nil when there's none.
        func presentationAnchor() -> PostHogPresentationAnchor? {
            var readableFrom: CALayer? = self
            var ancestor: CALayer? = self
            while let current = ancestor {
                if !Self.canCopyPresentation(of: current) { readableFrom = current.superlayer }
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

        /// This layer as presented, for reading its own values: its presentation copy, or the model while it has
        /// none (not committed yet) or its class can't be copied and nothing animates it. nil when its class can't be
        /// copied and an animation runs. Not for converting or reading `superlayer`: see `presentationAnchor`.
        var presentedValues: CALayer? {
            guard Self.canCopyPresentation(of: self) else { return animationKeys() == nil ? self : nil }
            return presentation() ?? self
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

        /// Whether rendering this layer's presentation copies no layer whose class `canCopyPresentation` rejects:
        /// rendering it copies every sublayer and mask under it.
        var canRenderPresentationTree: Bool {
            guard Self.canCopyPresentation(of: self), mask?.canRenderPresentationTree ?? true else { return false }
            return sublayers?.allSatisfy(\.canRenderPresentationTree) ?? true
        }

        /// `presentation()` can trap on an app's own layer subclass (see `PostHogGPUMirrorCapture.isPresentationSafe`).
        static func canCopyPresentation(of layer: CALayer) -> Bool {
            #if canImport(Metal)
                PostHogGPUMirrorCapture.isPresentationSafe(type(of: layer))
            #else
                false
            #endif
        }

        /// How far past `bounds` the layer draws, given `content`, the extent of its own drawing
        /// in bounds coordinates. A shadow without a `shadowPath` repeats the content's shape,
        /// text included, so it counts; `masksToBounds` clips the shadow away.
        /// Either the model's shadow or the presentation's can be drawn (the GPU capture copies the
        /// presentation's, mid-animation or before a commit), so the larger of the two counts.
        func drawnOutsets(of content: CGRect) -> UIEdgeInsets {
            let clips = masksToBounds
            let modelOutsets = Self.outsets(of: self, content: content, clips: clips)
            guard Self.canCopyPresentation(of: self), let presented = presentation() else { return modelOutsets }
            let presentedOutsets = Self.outsets(of: presented, content: presented.bounds.outset(by: Self.outsets(of: content, past: bounds)),
                                                clips: clips && presented.masksToBounds)
            return UIEdgeInsets(top: max(modelOutsets.top, presentedOutsets.top), left: max(modelOutsets.left, presentedOutsets.left),
                                bottom: max(modelOutsets.bottom, presentedOutsets.bottom), right: max(modelOutsets.right, presentedOutsets.right))
        }

        private static func outsets(of layer: CALayer, content: CGRect, clips: Bool) -> UIEdgeInsets {
            var drawn = content
            if !clips, layer.shadowOpacity > 0, layer.shadowColor != nil, layer.shadowPath == nil {
                // Pad by twice the blur radius so the shadow's soft edge is covered too.
                let blur = layer.shadowRadius * 2
                drawn = drawn.union(
                    content.offsetBy(dx: layer.shadowOffset.width, dy: layer.shadowOffset.height).insetBy(dx: -blur, dy: -blur)
                )
            }
            return outsets(of: drawn, past: layer.bounds)
        }

        fileprivate static func outsets(of drawn: CGRect, past bounds: CGRect) -> UIEdgeInsets {
            UIEdgeInsets(
                top: max(0, bounds.minY - drawn.minY),
                left: max(0, bounds.minX - drawn.minX),
                bottom: max(0, drawn.maxY - bounds.maxY),
                right: max(0, drawn.maxX - bounds.maxX)
            )
        }

        /// Backing flag for the SwiftUI `.postHogNoRageClick()` modifier on layer-backed
        /// views. Owner-set backed, same as the UIView flag.
        var postHogNoRageClick: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoRageClick)
        }

        func setPostHogNoRageClick(_ enabled: Bool, owner: UIView) {
            setPostHogFlag(&AssociatedKeys.phNoRageClick, enabled: enabled, owner: owner)
        }
    }
#endif
