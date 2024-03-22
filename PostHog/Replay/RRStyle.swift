// swiftlint:disable cyclomatic_complexity

//
//  RRStyle.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import Foundation

class RRStyle {
    var color: String?
    var backgroundColor: String?
    var backgroundImage: String?
    var borderWidth: Int?
    var borderRadius: Int?
    var borderColor: String?
    var fontSize: Int?
    var fontFamily: String?
    var horizontalAlign: String?
    var verticalAlign: String?
    var paddingTop: Int?
    var paddingBottom: Int?
    var paddingLeft: Int?
    var paddingRight: Int?
    var bar: String?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let color = color {
            dict["color"] = color
        }

        if let backgroundColor = backgroundColor {
            dict["backgroundColor"] = backgroundColor
        }

        if let backgroundImage = backgroundImage {
            dict["backgroundImage"] = backgroundImage
        }

        if let borderWidth = borderWidth {
            dict["borderWidth"] = borderWidth
        }

        if let borderRadius = borderRadius {
            dict["borderRadius"] = borderRadius
        }

        if let borderColor = borderColor {
            dict["borderColor"] = borderColor
        }

        if let fontSize = fontSize {
            dict["fontSize"] = fontSize
        }

        if let fontFamily = fontFamily {
            dict["fontFamily"] = fontFamily
        }

        if let horizontalAlign = horizontalAlign {
            dict["horizontalAlign"] = horizontalAlign
        }

        if let verticalAlign = verticalAlign {
            dict["verticalAlign"] = verticalAlign
        }

        if let paddingTop = paddingTop {
            dict["paddingTop"] = paddingTop
        }

        if let paddingBottom = paddingBottom {
            dict["paddingBottom"] = paddingBottom
        }

        if let paddingLeft = paddingLeft {
            dict["paddingLeft"] = paddingLeft
        }

        if let paddingRight = paddingRight {
            dict["paddingRight"] = paddingRight
        }

        if let bar = bar {
            dict["bar"] = bar
        }

        return dict
    }
}

// swiftlint:enable cyclomatic_complexity
