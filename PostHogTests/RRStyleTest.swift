//
//  RRStyleTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("RRStyle Tests")
struct RRStyleTest {
    @Suite("toDict")
    struct ToDictTests {
        @Test("returns an empty dictionary when nothing is set")
        func emptyWhenNothingSet() {
            #expect(RRStyle().toDict().isEmpty)
        }

        @Test("includes all fields when everything is set")
        func includesAllFields() {
            let style = RRStyle()
            style.color = "#FFFFFF"
            style.backgroundColor = "#1C1C1E"
            style.backgroundImage = "url(https://example.com/background.png)"
            style.borderWidth = 1
            style.borderRadius = 8
            style.borderColor = "#D1D1D6"
            style.fontSize = 17
            style.fontFamily = "Helvetica Neue"
            style.horizontalAlign = "center"
            style.verticalAlign = "center"
            style.paddingTop = 8
            style.paddingBottom = 8
            style.paddingLeft = 16
            style.paddingRight = 16
            style.bar = "horizontal"

            let dict = style.toDict()

            #expect(dict["color"] as? String == "#FFFFFF")
            #expect(dict["backgroundColor"] as? String == "#1C1C1E")
            #expect(dict["backgroundImage"] as? String == "url(https://example.com/background.png)")
            #expect(dict["borderWidth"] as? Int == 1)
            #expect(dict["borderRadius"] as? Int == 8)
            #expect(dict["borderColor"] as? String == "#D1D1D6")
            #expect(dict["fontSize"] as? Int == 17)
            #expect(dict["fontFamily"] as? String == "Helvetica Neue")
            #expect(dict["horizontalAlign"] as? String == "center")
            #expect(dict["verticalAlign"] as? String == "center")
            #expect(dict["paddingTop"] as? Int == 8)
            #expect(dict["paddingBottom"] as? Int == 8)
            #expect(dict["paddingLeft"] as? Int == 16)
            #expect(dict["paddingRight"] as? Int == 16)
            #expect(dict["bar"] as? String == "horizontal")
            #expect(dict.count == 15)
        }

        @Test("a single field only produces its own key", arguments: [
            ("color", { (s: RRStyle) in s.color = "#000000" }, "#000000"),
            ("backgroundColor", { (s: RRStyle) in s.backgroundColor = "#F2F2F7" }, "#F2F2F7"),
            ("backgroundImage", { (s: RRStyle) in s.backgroundImage = "url(https://example.com/background.png)" }, "url(https://example.com/background.png)"),
            ("borderWidth", { (s: RRStyle) in s.borderWidth = 1 }, "1"),
            ("borderRadius", { (s: RRStyle) in s.borderRadius = 8 }, "8"),
            ("borderColor", { (s: RRStyle) in s.borderColor = "#D1D1D6" }, "#D1D1D6"),
            ("fontSize", { (s: RRStyle) in s.fontSize = 17 }, "17"),
            ("fontFamily", { (s: RRStyle) in s.fontFamily = "Helvetica Neue" }, "Helvetica Neue"),
            ("horizontalAlign", { (s: RRStyle) in s.horizontalAlign = "left" }, "left"),
            ("verticalAlign", { (s: RRStyle) in s.verticalAlign = "center" }, "center"),
            ("paddingTop", { (s: RRStyle) in s.paddingTop = 8 }, "8"),
            ("paddingBottom", { (s: RRStyle) in s.paddingBottom = 8 }, "8"),
            ("paddingLeft", { (s: RRStyle) in s.paddingLeft = 16 }, "16"),
            ("paddingRight", { (s: RRStyle) in s.paddingRight = 16 }, "16"),
            ("bar", { (s: RRStyle) in s.bar = "circular" }, "circular"),
        ])
        func singleFieldOnlyProducesItsOwnKey(key: String, set: (RRStyle) -> Void, expected: String) {
            let style = RRStyle()
            set(style)

            let dict = style.toDict()

            #expect(dict.count == 1)
            #expect(dict[key].map { String(describing: $0) } == expected)
        }

        @Test("omits keys for nil fields in a partially set style")
        func omitsNilFields() {
            let style = RRStyle()
            style.color = "#FFFFFF"
            style.fontSize = 17

            let dict = style.toDict()

            #expect(Set(dict.keys) == ["color", "fontSize"])
            #expect(dict["color"] as? String == "#FFFFFF")
            #expect(dict["fontSize"] as? Int == 17)
            #expect(!dict.values.contains { $0 is NSNull })
        }

        @Test("keeps zero values")
        func keepsZeroValues() {
            let style = RRStyle()
            style.borderWidth = 0
            style.borderRadius = 0
            style.paddingTop = 0

            let dict = style.toDict()

            #expect(dict["borderWidth"] as? Int == 0)
            #expect(dict["borderRadius"] as? Int == 0)
            #expect(dict["paddingTop"] as? Int == 0)
            #expect(dict.count == 3)
        }
    }
}
