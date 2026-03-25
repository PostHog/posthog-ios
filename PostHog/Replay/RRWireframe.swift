// swiftlint:disable cyclomatic_complexity

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
        private func maskImage() -> UIImage? {
            guard let image = image else { return nil }

            // Skip re-rendering entirely when there are no widgets to mask —
            // avoids creating a full-size copy of the image just to draw it back unchanged
            guard let maskableWidgets = maskableWidgets, !maskableWidgets.isEmpty else {
                return nil
            }

            // Use custom CGContext renderer for masking — faster than UIGraphicsImageRenderer.
            // Use scale=1 since we only need to draw masking rects over the existing image.
            let renderer = PostHogGraphicsImageRenderer(size: image.size, scale: 1)
            return renderer.image { context in
                context.interpolationQuality = .none
                image.draw(at: .zero)

                for rect in maskableWidgets {
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                    UIColor.black.setFill()
                    path.fill()
                }
            }
        }
    #endif

    func toDict() -> [String: Any] {
        // Pre-size with enough capacity for all possible keys to avoid rehashing
        var dict = [String: Any](minimumCapacity: 16)
        dict["id"] = id
        dict["x"] = posX
        dict["y"] = posY
        dict["width"] = width
        dict["height"] = height

        if let childWireframes = childWireframes {
            dict["childWireframes"] = childWireframes.map { $0.toDict() }
        }

        if let type = type {
            dict["type"] = type
        }

        if let inputType = inputType {
            dict["inputType"] = inputType
        }

        if let text = text {
            dict["text"] = text
        }

        if let label = label {
            dict["label"] = label
        }

        if let value = value {
            dict["value"] = value
        }

        #if os(iOS)
            if let image = image {
                if let maskedImage = maskImage() {
                    // Release original image before encoding to reduce peak memory
                    self.image = nil
                    base64 = maskedImage.toBase64()
                } else {
                    base64 = image.toBase64()
                    // Release original image after encoding
                    self.image = nil
                }
                // maskableWidgets no longer needed after masking is done
                maskableWidgets = nil
            }
        #endif

        if let base64 = base64 {
            dict["base64"] = base64
        }

        if let style = style {
            dict["style"] = style.toDict()
        }

        if let disabled = disabled {
            dict["disabled"] = disabled
        }

        if let checked = checked {
            dict["checked"] = checked
        }

        if let options = options {
            dict["options"] = options
        }

        if let max = max {
            dict["max"] = max
        }

        return dict
    }
}

// swiftlint:enable cyclomatic_complexity
