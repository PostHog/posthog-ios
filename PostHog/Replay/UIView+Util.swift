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

        func isNoCapture() -> Bool {
            containsAccessibilityToken("ph-no-capture")
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
                        // drawHierarchy lags the render server's displayed frame, so mask rects would
                        // sit ahead of the pixels during scroll or animation. The presentation tree is
                        // the same source toAbsoluteRect measures, at the same instant — masks and
                        // pixels can't disagree. Trade-off: blur/video/Metal render flat or empty.
                        //
                        // Known limitation: render(in:) skips filters, backgroundFilters and
                        // layer.mask, so anything relying on a blur or a layer mask to hide content
                        // draws unhidden here. Whether a blur is redaction or decoration isn't
                        // knowable from the view, so this isn't detected — content that must never
                        // appear needs postHogMask().
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
        /// mask rects have to come from the presentation tree. Wireframe geometry is a separate
        /// consumer with no pixels to agree with and stays on `toAbsoluteRect`.
        func toPresentationRect(_ window: UIWindow?) -> CGRect {
            guard layer.presentation() != nil else {
                // UIView's own convert, not the layer's: it resolves a nil window to the view's.
                return convert(bounds, to: window)
            }
            return layer.toPresentationRect(window)
        }
    }

    extension CALayer {
        func toPresentationRect(_ window: UIWindow?) -> CGRect {
            guard let presentationLayer = presentation() else {
                return convert(bounds, to: window?.layer)
            }
            return presentationLayer.convert(presentationLayer.bounds, to: window?.layer.presentation() ?? window?.layer)
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
