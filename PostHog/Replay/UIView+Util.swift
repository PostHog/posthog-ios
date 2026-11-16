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
            // An app-defined layer that's animating can't be read, so it isn't taken as collapsed.
            if frame == .zero, clipsToBounds,
               layer.readablePresentation.map(\.bounds.isEmpty) ?? (!layer.isAppDefined && bounds.isEmpty)
            {
                return false
            }
            return true
        }

        /// Whether the screenshot draws this view at all. During an opacity animation the
        /// model `alpha` sits at the destination while the presentation layer holds the
        /// in-flight value the screenshot renders, so a view fading out reads as opaque
        /// here. The model value comes first, so `presentation()` — which copies the layer —
        /// is only paid for on a view that is already transparent.
        var hasRenderedOpacity: Bool {
            if alpha > 0 {
                return true
            }
            guard let presentationOpacity = layer.readablePresentation?.opacity else {
                // An app-defined layer animating can't be read, so it counts as drawn and stays masked.
                return layer.isAppDefined
            }
            return presentationOpacity > 0
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

            // Rendering the presentation tree copies every layer in it, which can trap on an app-defined one.
            if !afterScreenUpdates, screenshotRenderer == .presentationTree, layer.containsAppDefinedLayer {
                hedgeLog("[Session Replay] Skipping snapshot: the window holds an app-defined layer the motion renderer can't copy")
                return nil
            }

            // Use native screen scale and gamut for best drawHierarchy performance.
            // Using a non-native scale can trigger internal rescaling overhead, and a bitmap in
            // another gamut makes drawHierarchy convert every pixel on the main thread.
            let nativeScale = (self as? UIWindow ?? window)?.screen.scale ?? 1
            let drawsHierarchy = afterScreenUpdates || screenshotRenderer == .fidelity
            let gamut = screenshotGamut(drawingHierarchy: drawsHierarchy)
            let renderer = PostHogGraphicsImageRenderer(size: size, scale: nativeScale, gamut: gamut)

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

        func screenshotGamut(drawingHierarchy: Bool) -> UIDisplayGamut {
            guard drawingHierarchy, let screen = (self as? UIWindow ?? window)?.screen else {
                return .unspecified
            }
            return screen.traitCollection.displayGamut
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
            if layer.hasAppDefinedLayerInChain {
                return layer.failingClosedWhileAnimating(convert(bounds.outset(by: outsets), to: window), in: window)
            }
            guard layer.presentation() != nil else {
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
        /// skipped: content that must stay hidden needs `postHogMask()`.
        case presentationTree
    }

    extension UIImageView {
        /// The union of the bounds and where each image the view can draw lands, in bounds
        /// coordinates. Only fill-to-bounds content modes keep the image inside the bounds.
        var drawnImageExtent: CGRect {
            switch contentMode {
            case .scaleToFill, .scaleAspectFit, .redraw:
                return bounds
            default:
                return imageSources.reduce(bounds) { $0.union(drawnRect(ofImageSized: $1.size)) }
            }
        }

        /// Every image the view is set to draw.
        var imageSources: [UIImage] {
            [image, highlightedImage].compactMap { $0 } + (animationImages ?? []) + (highlightedAnimationImages ?? [])
        }

        /// Whether an animation on the layer draws an image the view isn't set to draw, such as a transition's
        /// cached previous image.
        var animatesReplacedImage: Bool {
            layer.animatesContents(outside: imageSources.compactMap(\.cgImage))
        }

        /// Where an image replaced since the last commit lands, in bounds coordinates: the presentation layer still
        /// holds it, and the default capture draws it. Measured on the presented layer, whose bounds, gravity and
        /// contents rect place it. A gravity that scales the contents to the bounds keeps them inside (nil). Otherwise
        /// the layer may draw them rotated or flipped (an EXIF orientation), which the public API doesn't expose, so
        /// the measured extent grows by the contents' longest drawn side: a turned copy anchored by the same gravity
        /// can't land further out. Contents whose size can't be read reach arbitrarily far. Nil when nothing was
        /// replaced.
        var replacedImageExtent: CGRect? {
            // An app-defined layer's presentation can't be read, and an animation can draw an image the view no longer
            // holds, so an image replaced since the last commit can't be measured.
            if layer.isAppDefined || animatesReplacedImage {
                let gravity = layer.contentsGravity
                if gravity == .resize || gravity == .resizeAspect {
                    return nil
                }
                return bounds.insetBy(dx: -Self.unmeasuredImageReach, dy: -Self.unmeasuredImageReach)
            }
            guard let presented = layer.readablePresentation, let contents = presented.contents,
                  layer.contents.map({ $0 as AnyObject !== contents as AnyObject }) ?? true
            else { return nil }
            let gravity = presented.contentsGravity
            if gravity == .resize || gravity == .resizeAspect {
                return nil
            }
            let presentedBounds = presented.bounds
            let extent: CGRect
            if let size = CALayer.contentsSize(presented, contents: contents) {
                let drawn = CALayer.drawnSize(of: size, gravity: gravity, in: presentedBounds)
                let turned = CALayer.drawnSize(of: CGSize(width: size.height, height: size.width), gravity: gravity, in: presentedBounds)
                let reach = max(drawn.width, drawn.height, turned.width, turned.height)
                extent = presentedBounds.insetBy(dx: -max(0, drawn.width - presentedBounds.width) - reach,
                                                 dy: -max(0, drawn.height - presentedBounds.height) - reach)
            } else {
                extent = presentedBounds.insetBy(dx: -Self.unmeasuredImageReach, dy: -Self.unmeasuredImageReach)
            }
            return bounds.outset(by: CALayer.outsets(of: extent, past: presentedBounds))
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

    extension CALayer {
        func toPresentationRect(_ window: UIWindow?, outsets: UIEdgeInsets = .zero) -> CGRect {
            if hasAppDefinedLayerInChain {
                return failingClosedWhileAnimating(convert(bounds.outset(by: outsets), to: window?.layer), in: window)
            }
            guard let presentationLayer = presentation() else {
                return convert(bounds.outset(by: outsets), to: window?.layer)
            }
            return presentationLayer.convert(
                presentationLayer.bounds.outset(by: outsets),
                to: window?.layer.presentation() ?? window?.layer
            )
        }

        /// Whether the app defines this layer's class. `presentation()` copies a layer through its class's
        /// `init(layer:)`, which traps for a Swift subclass that declares its own initializer but not that one. The
        /// runtime can't tell that subclass from one that implements it, so every class whose `initWithLayer:` comes
        /// from neither CALayer nor a system image counts.
        var isAppDefined: Bool {
            Self.isAppDefined(type(of: self))
        }

        /// The layer as the screen shows it, read without copying an app-defined layer: `presentation()` for a system
        /// layer (nil before its first commit), the model for an app-defined one while nothing animates it, and nil
        /// while something does. Callers treat an unreadable app-defined layer as drawn, so it stays masked.
        var readablePresentation: CALayer? {
            guard isAppDefined else { return presentation() }
            return animationKeys() == nil ? self : nil
        }

        /// Whether this layer or an ancestor is app-defined. Converting a presentation copies every ancestor's.
        var hasAppDefinedLayerInChain: Bool {
            isAppDefined || superlayer?.hasAppDefinedLayerInChain == true
        }

        /// Whether this layer or a sublayer, at any depth, is app-defined. Rendering a presentation copies them all.
        var containsAppDefinedLayer: Bool {
            isAppDefined || mask?.containsAppDefinedLayer == true || sublayers?.contains(where: \.containsAppDefinedLayer) == true
        }

        /// `modelRect` for a layer in an app-defined chain, whose presentation can't be read. The model matches the
        /// screen only while nothing in the chain animates; while something does, the mask covers the whole window.
        func failingClosedWhileAnimating(_ modelRect: CGRect, in window: UIWindow?) -> CGRect {
            hasAnimationInChain ? modelRect.union(window?.bounds ?? modelRect) : modelRect
        }

        /// Whether an animation on this layer draws contents other than `known`, read off the animations without
        /// copying the layer: a `CATransition` draws the cached previous contents, and a `contents` animation draws
        /// its values, or the previous contents when it has no `fromValue`.
        func animatesContents(outside known: @autoclosure () -> [AnyObject]) -> Bool {
            guard let keys = animationKeys() else { return false }
            let knownIDs = Set(known().map(ObjectIdentifier.init))
            func isKnown(_ value: Any) -> Bool {
                knownIDs.contains(ObjectIdentifier(value as AnyObject))
            }
            return keys.contains { key in
                switch animation(forKey: key) {
                case is CATransition:
                    return true
                case let keyframes as CAKeyframeAnimation where keyframes.keyPath == "contents":
                    return !(keyframes.values ?? []).allSatisfy(isKnown)
                case let basic as CABasicAnimation where basic.keyPath == "contents":
                    guard let from = basic.fromValue else { return true }
                    return ![from, basic.toValue, basic.byValue].compactMap { $0 }.allSatisfy(isKnown)
                default:
                    return false
                }
            } == true
        }

        /// Whether this layer or an ancestor has an animation, so the model may not match the screen.
        var hasAnimationInChain: Bool {
            animationKeys() != nil || superlayer?.hasAnimationInChain == true
        }

        private static func isAppDefined(_ cls: AnyClass) -> Bool {
            let key = ObjectIdentifier(cls)
            appDefinedLock.lock()
            defer { appDefinedLock.unlock() }
            if let cached = appDefinedClasses[key] {
                return cached
            }
            let appDefined = !hasSystemInitWithLayer(cls)
            appDefinedClasses[key] = appDefined
            return appDefined
        }

        private static let appDefinedLock = NSLock()
        private static var appDefinedClasses: [ObjectIdentifier: Bool] = [:]

        private static func hasSystemInitWithLayer(_ cls: AnyClass) -> Bool {
            let selector = NSSelectorFromString("initWithLayer:")
            let implementation = class_getMethodImplementation(cls, selector)
            if implementation == class_getMethodImplementation(CALayer.self, selector) {
                return true
            }
            var info = Dl_info()
            guard let implementation, dladdr(unsafeBitCast(implementation, to: UnsafeRawPointer.self), &info) != 0,
                  let image = info.dli_fname
            else {
                return false
            }
            let path = String(cString: image)
            return path.contains("/System/Library/") || path.contains("/usr/lib/")
        }

        /// The size `contents` draws at before gravity places it, in points. Nil for contents the layer draws itself.
        static func contentsSize(_ layer: CALayer, contents: Any) -> CGSize? {
            let object = contents as AnyObject
            let typeID = CFGetTypeID(object)
            let pixels: CGSize
            if typeID == CGImage.typeID {
                let image = object as! CGImage
                pixels = CGSize(width: image.width, height: image.height)
            } else if typeID == IOSurfaceGetTypeID() {
                let surface = object as! IOSurfaceRef
                pixels = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
            } else {
                return nil
            }
            let scale = layer.contentsScale > 0 ? layer.contentsScale : 1
            return CGSize(width: pixels.width / scale * layer.contentsRect.width, height: pixels.height / scale * layer.contentsRect.height)
        }

        /// The size contents of `size` draw at under a `gravity` that doesn't scale them to `bounds`.
        static func drawnSize(of size: CGSize, gravity: CALayerContentsGravity, in bounds: CGRect) -> CGSize {
            guard gravity == .resizeAspectFill, size.width > 0, size.height > 0 else { return size }
            let fill = max(bounds.width / size.width, bounds.height / size.height)
            return CGSize(width: size.width * fill, height: size.height * fill)
        }

        fileprivate static func outsets(of drawn: CGRect, past bounds: CGRect) -> UIEdgeInsets {
            UIEdgeInsets(
                top: max(0, bounds.minY - drawn.minY),
                left: max(0, bounds.minX - drawn.minX),
                bottom: max(0, drawn.maxY - bounds.maxY),
                right: max(0, drawn.maxX - bounds.maxX)
            )
        }

        /// How far past `bounds` the layer draws, given `content`, the extent of its own drawing
        /// in bounds coordinates. A shadow without a `shadowPath` repeats the content's shape,
        /// text included, so it counts; `masksToBounds` clips the shadow away.
        /// Either the model's shadow or the presentation's can be drawn (the GPU capture copies the
        /// presentation's, mid-animation or before a commit), so the larger of the two counts. An app-defined layer's
        /// presentation isn't copied: while one animates, its mask already spans the window.
        func drawnOutsets(of content: CGRect) -> UIEdgeInsets {
            let clips = masksToBounds
            let modelOutsets = Self.outsets(of: self, content: content, clips: clips)
            guard let presented = readablePresentation else { return modelOutsets }
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
