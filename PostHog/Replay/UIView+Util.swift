//
//  UIView+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS)
    import Foundation
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
            if frame == .zero, clipsToBounds, (layer.presentation()?.bounds ?? bounds).isEmpty {
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
            guard let presentationOpacity = layer.presentation()?.opacity else {
                return false
            }
            return presentationOpacity > 0
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
            // Replay callers render on main; the sync is defensive, since controller traversal belongs on main.
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

            return autoreleasepool {
                renderer.image { context in
                    if afterScreenUpdates {
                        /// The bridge capture passes `true`: a freshly-presented native VC renders black otherwise.
                        drawHierarchy(in: bounds, afterScreenUpdates: true)
                    } else if preferFidelityRenderer {
                        // Chosen when the settle check measured little enough movement that the
                        // displayed frame still matches the current tree, so drawHierarchy's
                        // full fidelity (blur, video, Metal) is worth lagging the render server.
                        drawHierarchy(in: bounds, afterScreenUpdates: false)
                    } else {
                        // drawHierarchy lags the render server, so mask rects could sit ahead of
                        // the pixels during scroll or animation; the presentation tree is the same
                        // source toPresentationRect measures, at the same instant, so the two agree.
                        // Trade-off: blur, video and Metal render flat, and render(in:) also skips
                        // filters and layer.mask — content that must stay hidden needs postHogMask().
                        (layer.presentation() ?? layer).render(in: context)
                    }
                }
            }
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ window: UIWindow?) -> CGRect {
            convert(bounds, to: window)
        }

        /// Mask geometry only. During a CA animation the model layer parks at the destination
        /// while the presentation layer holds the in-flight position the screenshot renders, so
        /// mask rects have to come from the presentation tree.
        /// `outsets` grows the rect past the bounds, for content drawn outside them.
        func toPresentationRect(_ window: UIWindow?, outsets: UIEdgeInsets = .zero) -> CGRect {
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
                content = imageView.drawnImageExtent
            }
            return layer.drawnOutsets(of: content)
        }
    }

    extension UIImageView {
        /// The union of the bounds and where each image the view can draw lands, in bounds
        /// coordinates. Only fill-to-bounds content modes keep the image inside the bounds.
        var drawnImageExtent: CGRect {
            switch contentMode {
            case .scaleToFill, .scaleAspectFit, .redraw:
                return bounds
            default:
                let sources = [image, highlightedImage].compactMap { $0 }
                    + (animationImages ?? []) + (highlightedAnimationImages ?? [])
                return sources.reduce(bounds) { $0.union(drawnRect(ofImageSized: $1.size)) }
            }
        }

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
            guard let presentationLayer = presentation() else {
                return convert(bounds.outset(by: outsets), to: window?.layer)
            }
            return presentationLayer.convert(
                presentationLayer.bounds.outset(by: outsets),
                to: window?.layer.presentation() ?? window?.layer
            )
        }

        /// How far past `bounds` the layer draws, given `content`, the extent of its own drawing
        /// in bounds coordinates. A shadow without a `shadowPath` repeats the content's shape,
        /// text included, so it counts; `masksToBounds` clips the shadow away.
        func drawnOutsets(of content: CGRect) -> UIEdgeInsets {
            var drawn = content
            if !masksToBounds, shadowOpacity > 0, shadowColor != nil, shadowPath == nil {
                // Pad by twice the blur radius so the shadow's soft edge is covered too.
                let blur = shadowRadius * 2
                drawn = drawn.union(
                    content.offsetBy(dx: shadowOffset.width, dy: shadowOffset.height).insetBy(dx: -blur, dy: -blur)
                )
            }
            return UIEdgeInsets(
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
