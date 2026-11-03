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

        dict["color"] = color
        dict["backgroundColor"] = backgroundColor
        dict["backgroundImage"] = backgroundImage
        dict["borderWidth"] = borderWidth
        dict["borderRadius"] = borderRadius
        dict["borderColor"] = borderColor
        dict["fontSize"] = fontSize
        dict["fontFamily"] = fontFamily
        dict["horizontalAlign"] = horizontalAlign
        dict["verticalAlign"] = verticalAlign
        dict["paddingTop"] = paddingTop
        dict["paddingBottom"] = paddingBottom
        dict["paddingLeft"] = paddingLeft
        dict["paddingRight"] = paddingRight
        dict["bar"] = bar

        return dict
    }
}
