// swiftlint:disable cyclomatic_complexity

//
//  RRWireframe.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import Foundation
import UIKit

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
    var image: UIImage? // clean reference after using it
    var maskableWidgets: [CGRect]?
    var base64: String?
    var style: RRStyle?
    var disabled: Bool?
    var checked: Bool?
    var options: [String]?
    var max: Int?
    // internal
    var parentId: Int?
    
    private func imageToBase64(_ image: UIImage) -> String? {
        let jpegData = image.jpegData(compressionQuality: 0.3)
        let base64 = jpegData?.base64EncodedString()

        if let base64 = base64 {
            return "data:image/jpeg;base64,\(base64)"
        }

        return nil
    }
    
    private func maskImage() -> UIImage? {
        if let image = image {
            if let maskableWidgets = maskableWidgets {
                let redactedImage = UIGraphicsImageRenderer(size: image.size, format: .init(for: .init(displayScale: 1))).image { context in
                    context.cgContext.interpolationQuality = .none
                    image.draw(at: .zero)

                    for rect in maskableWidgets {
                        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                        UIColor.black.setFill()
                        path.fill()
                    }
                }
                return redactedImage
            }
        }
        return nil
    }

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
        
        if let image = image {
            if let maskedImage = maskImage() {
                base64 = imageToBase64(maskedImage)
            } else {
                base64 = imageToBase64(image)
            }
        }
        image = nil

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
