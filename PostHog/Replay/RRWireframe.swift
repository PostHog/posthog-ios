//
//  RRWireframe.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import Foundation
#if os(iOS)
    import UIKit
#endif

class RRWireframe {
    var id: Int = 0
    var posX: Int = 0
    var posY: Int = 0
    var width: Int = 0
    var height: Int = 0
    var childWireframes: [RRWireframe]?
    var type: String? // text|image|rectangle|input|div|screenshot
    var inputType: String?
    var text: String?
    var label: String?
    var value: Any? // string or number
    #if os(iOS)
        var image: UIImage?
        var maskableWidgets: [CGRect]?
        var screenshotPixelScale: CGFloat = 1
        /// Set by `toDict()` when mask rects were collected but the redacted image could not
        /// be rendered. The caller must drop the frame: the wireframe carries no image, and
        /// the raw screenshot would show masked content.
        private(set) var maskRenderFailed = false
    #endif
    var base64: String?
    var style: RRStyle?
    var disabled: Bool?
    var checked: Bool?
    var options: [String]?
    var max: Int?
    // internal
    var parentId: Int?

    #if os(iOS)
        private func hasMaskableWidgets() -> Bool {
            guard let maskableWidgets else {
                return false
            }

            return !maskableWidgets.isEmpty
        }

        private func maskImage() -> UIImage? {
            guard hasMaskableWidgets(), let image else {
                return nil
            }
            return RRWireframe.maskImage(image, maskableWidgets: maskableWidgets ?? [], pixelScale: screenshotPixelScale)
        }

        // Shared so tests can redact through the exact production path instead of reimplementing it.
        static func maskImage(_ image: UIImage, maskableWidgets: [CGRect], pixelScale: CGFloat = 1) -> UIImage? {
            guard !maskableWidgets.isEmpty else { return nil }
            return redraw(image, pixelScale: pixelScale, maskableWidgets: maskableWidgets)
        }

        /// Screenshots render at native scale on main; this resize runs at encode time, off main,
        /// so every screenshot uploads at the same size whether or not it is masked.
        private static func redraw(_ image: UIImage, pixelScale: CGFloat, maskableWidgets: [CGRect] = []) -> UIImage? {
            autoreleasepool {
                let renderer = PostHogGraphicsImageRenderer(size: image.size, scale: pixelScale, roundingUp: true)
                return renderer.image { context in
                    // Nearest-neighbour drops thin glyph stems when downsampling.
                    context.interpolationQuality = .medium
                    image.draw(at: .zero)

                    // Whole output pixels, so a mask edge that falls mid-pixel can't blend into it.
                    let toPixels = context.userSpaceToDeviceSpaceTransform
                    let toPoints = toPixels.inverted()
                    for rect in maskableWidgets {
                        UIColor.black.setFill()
                        UIRectFill(rect.applying(toPixels).integral.applying(toPoints))
                    }
                }
            }
        }

        /// Nothing to hide, so unlike masking a failed redraw can fall back to the native image.
        static func unmaskedScreenshot(_ image: UIImage, pixelScale: CGFloat) -> UIImage {
            // Already at the upload resolution, so a redraw would only cost time.
            guard pixelScale < image.scale else { return image }
            return redraw(image, pixelScale: pixelScale) ?? image
        }
    #endif

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "x": posX,
            "y": posY,
            "width": width,
            "height": height,
        ]

        if let childWireframes = childWireframes {
            dict["childWireframes"] = childWireframes.map { $0.toDict() }
        }

        dict["type"] = type

        dict["inputType"] = inputType

        dict["text"] = text

        dict["label"] = label

        if let value = value {
            dict["value"] = value
        }

        #if os(iOS)
            if let image = image {
                if hasMaskableWidgets() {
                    if let maskedImage = maskImage() {
                        base64 = maskedImage.toBase64()
                    } else {
                        // Renderer allocation can fail under memory pressure. Leave base64
                        // unset and let the caller drop the frame — never the raw image.
                        maskRenderFailed = true
                    }
                } else if type == "screenshot" {
                    base64 = RRWireframe.unmaskedScreenshot(image, pixelScale: screenshotPixelScale).toBase64()
                } else {
                    base64 = image.toBase64()
                }

                self.image = nil
                maskableWidgets = nil
            }
        #endif

        dict["base64"] = base64

        if let style = style {
            dict["style"] = style.toDict()
        }

        dict["disabled"] = disabled

        dict["checked"] = checked

        dict["options"] = options

        dict["max"] = max

        return dict
    }
}
