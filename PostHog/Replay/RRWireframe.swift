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
    var type: String? // screenshot
    #if os(iOS)
        var image: UIImage?
        var maskableWidgets: [CGRect]?
        /// Set by `toDict()` when mask rects were collected but the redacted image could not
        /// be rendered. The caller must drop the frame: the wireframe carries no image, and
        /// the raw screenshot would show masked content.
        private(set) var maskRenderFailed = false
    #endif
    var base64: String?

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
            return RRWireframe.maskImage(image, maskableWidgets: maskableWidgets ?? [])
        }

        // Shared so tests can redact through the exact production path instead of reimplementing it.
        static func maskImage(_ image: UIImage, maskableWidgets: [CGRect]) -> UIImage? {
            guard !maskableWidgets.isEmpty else { return nil }

            return autoreleasepool {
                // Use scale=1 to preserve the existing masked screenshot payload size.
                let renderer = PostHogGraphicsImageRenderer(size: image.size, scale: 1)
                return renderer.image { context in
                    context.interpolationQuality = .none
                    image.draw(at: .zero)

                    for rect in maskableWidgets {
                        UIColor.black.setFill()
                        UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
                    }
                }
            }
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

        if let type = type {
            dict["type"] = type
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
                } else {
                    base64 = image.toBase64()
                }

                self.image = nil
                maskableWidgets = nil
            }
        #endif

        if let base64 = base64 {
            dict["base64"] = base64
        }

        return dict
    }
}
