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

        func toImage(afterScreenUpdates: Bool = false, preferFidelityRenderer: Bool = true) -> UIImage? {
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
                    } else if preferFidelityRenderer {
                        // Chosen when the settle check measured little enough movement that the
                        // displayed frame still matches the current tree, so drawHierarchy's
                        // full fidelity (blur, video, Metal) is worth lagging the render server.
                        drawn = drawHierarchy(in: bounds, afterScreenUpdates: false)
                    } else {
                        // drawHierarchy lags the render server, so mask rects could sit ahead of
                        // the pixels during scroll or animation; the presentation tree is the same
                        // source toPresentationRect measures, at the same instant, so the two agree.
                        // Trade-off: blur, video and Metal render flat, and render(in:) also skips
                        // filters and layer.mask — content that must stay hidden needs postHogMask().
                        // Only for a layer that `canRenderPresentationTree`: copying the tree traps otherwise.
                        (layer.presentation() ?? layer).render(in: context)
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
            guard CALayer.canCopyPresentation(of: layer) else {
                return keepsImageInBounds ? nil : bounds.insetBy(dx: -Self.unmeasuredImageReach, dy: -Self.unmeasuredImageReach)
            }
            guard let presented = layer.presentation(), let contents = presented.contents,
                  layer.contents.map({ $0 as AnyObject !== contents as AnyObject }) ?? true
            else { return nil }
            let gravity = presented.contentsGravity
            let typeID = CFGetTypeID(contents as AnyObject)
            let extent: CGRect
            if CALayer.contentsTransformKey?.changedValue(in: presented) != nil
                || typeID != CGImage.typeID && typeID != IOSurfaceGetTypeID()
            {
                extent = presented.bounds.insetBy(dx: -Self.unmeasuredImageReach, dy: -Self.unmeasuredImageReach)
            } else if gravity == .resize || gravity == .resizeAspect {
                return nil
            } else {
                extent = CALayer.contentsExtent(presented, contents: contents, gravity: gravity, bounds: presented.bounds)
            }
            return bounds.outset(by: CALayer.outsets(of: extent, past: presented.bounds))
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
        /// Whether a layer above the measured one can't have its presentation copied.
        let hasUncopyableAncestor: Bool
    }

    /// A private CALayer property newer OSes draw with. Read through KVC, which CALayer answers for any key; nil where
    /// CALayer doesn't declare it, so older OSes skip it.
    struct PostHogPrivateLayerKey {
        let name: String
        private let defaultValue: NSObject?

        init?(_ name: String) {
            guard CALayer.instancesRespond(to: NSSelectorFromString(name)) else { return nil }
            self.name = name
            defaultValue = CALayer().value(forKey: name) as? NSObject
        }

        /// The layer's value when it differs from a fresh layer's.
        func changedValue(in layer: CALayer) -> NSObject? {
            guard let value = layer.value(forKey: name) as? NSObject, !value.isEqual(defaultValue) else { return nil }
            return value
        }
    }

    extension CALayer {
        func toPresentationRect(_ window: UIWindow?, outsets: UIEdgeInsets = .zero) -> CGRect {
            presentedRect(in: window?.layer, outsets: outsets).rect
        }

        /// `toPresentationRect` in `windowLayer`'s space. Below the presentation anchor only the model can be read, so
        /// under an ancestor whose presentation can't be copied, or while such a layer moves, the rect isn't exact and
        /// spans the window.
        func presentedRect(in windowLayer: CALayer?, outsets: UIEdgeInsets = .zero) -> (rect: CGRect, isExact: Bool) {
            guard let anchor = presentationAnchor() else { return (convert(bounds.outset(by: outsets), to: windowLayer), true) }
            let presentedWindow = windowLayer.map { $0.presentationAnchor()?.presented ?? $0 }
            if anchor.layer === self {
                return (anchor.presented.convert(anchor.presented.bounds.outset(by: outsets), to: presentedWindow), true)
            }
            let placed = anchor.presented.convert(convert(bounds.outset(by: outsets), to: anchor.layer), to: presentedWindow)
            if anchor.hasUncopyableAncestor || !Self.canCopyPresentation(of: self) && hasGeometricAnimation {
                return (placed.union((presentedWindow ?? rootLayer).bounds), false)
            }
            return (placed, true)
        }

        private var rootLayer: CALayer {
            superlayer?.rootLayer ?? self
        }

        /// The nearest layer above the topmost one whose presentation can't be copied that has a presentation (one not
        /// committed yet has none). Converting through a presentation copy copies every ancestor's too, which traps on
        /// such a layer. nil when there's none.
        func presentationAnchor() -> PostHogPresentationAnchor? {
            var readableFrom: CALayer? = self
            var hasUncopyableAncestor = false
            var ancestor: CALayer? = self
            while let current = ancestor {
                if !Self.canCopyPresentation(of: current) {
                    readableFrom = current.superlayer
                    hasUncopyableAncestor = hasUncopyableAncestor || current !== self
                }
                ancestor = current.superlayer
            }
            var isReadable = false
            var current: CALayer? = self
            while let layer = current {
                if layer === readableFrom { isReadable = true }
                if isReadable, let presented = layer.presentation() {
                    return PostHogPresentationAnchor(layer: layer, presented: presented, hasUncopyableAncestor: hasUncopyableAncestor)
                }
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

        /// Whether `presentation()` is safe to call on `layer` (see `isPresentationSafe`).
        static func canCopyPresentation(of layer: CALayer) -> Bool {
            isPresentationSafe(type(of: layer))
        }

        /// `presentation()` instantiates the layer's class through `initWithLayer:`; a Swift subclass that doesn't
        /// override `init(layer:)` traps there. CALayer's own implementation, and any that lives in a system image
        /// (found with `dladdr`, since the app's own subclasses are the ones that can trap), are trusted.
        static func isPresentationSafe(_ cls: AnyClass) -> Bool {
            let key = ObjectIdentifier(cls)
            presentationSafetyLock.lock()
            defer { presentationSafetyLock.unlock() }
            if let cached = presentationSafety[key] { return cached }
            let safe = hasSystemInitWithLayer(cls)
            presentationSafety[key] = safe
            return safe
        }

        private static let presentationSafetyLock = NSLock()
        private static var presentationSafety: [ObjectIdentifier: Bool] = [:]

        private static func hasSystemInitWithLayer(_ cls: AnyClass) -> Bool {
            let selector = NSSelectorFromString("initWithLayer:")
            let implementation = class_getMethodImplementation(cls, selector)
            if implementation == class_getMethodImplementation(CALayer.self, selector) { return true }
            var info = Dl_info()
            guard dladdr(unsafeBitCast(implementation, to: UnsafeRawPointer.self), &info) != 0, let name = info.dli_fname else { return false }
            let path = String(cString: name)
            return path.contains("/System/Library/") || path.contains("/usr/lib/")
        }

        /// Set on an image view's layer that draws its image rotated or flipped (an EXIF orientation), stored unrotated.
        static let contentsTransformKey = PostHogPrivateLayerKey("contentsTransform")

        /// Where `contents` drawn with a `gravity` that doesn't scale them to `bounds` lands, in `bounds`' space.
        static func contentsExtent(_ layer: CALayer, contents: Any, gravity: CALayerContentsGravity, bounds: CGRect) -> CGRect {
            let object = contents as AnyObject
            let typeID = CFGetTypeID(object)
            var size: CGSize
            if typeID == CGImage.typeID {
                let image = object as! CGImage
                size = CGSize(width: image.width, height: image.height)
            } else if typeID == IOSurfaceGetTypeID() {
                let surface = object as! IOSurfaceRef
                size = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
            } else {
                // Backing stores are drawn by the layer itself at its own size.
                return bounds
            }
            let scale = layer.contentsScale > 0 ? layer.contentsScale : 1
            size = CGSize(width: size.width / scale * layer.contentsRect.width, height: size.height / scale * layer.contentsRect.height)
            if gravity == .resizeAspectFill, size.width > 0, size.height > 0 {
                let fill = max(bounds.width / size.width, bounds.height / size.height)
                size = CGSize(width: size.width * fill, height: size.height * fill)
            }
            return bounds.insetBy(dx: -max(0, size.width - bounds.width), dy: -max(0, size.height - bounds.height))
        }

        /// How far past `bounds` the layer draws, given `content`, the extent of its own drawing
        /// in bounds coordinates. A shadow without a `shadowPath` repeats the content's shape,
        /// text included, so it counts; `masksToBounds` clips the shadow away.
        /// Mid-animation, or before a commit, the screenshot draws the presentation's shadow while the
        /// model already holds the next one, so the larger of the two counts.
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
