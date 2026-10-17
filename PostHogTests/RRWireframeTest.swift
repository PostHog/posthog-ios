//
//  RRWireframeTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("RRWireframe Tests")
struct RRWireframeTest {
    // A tiny base64 data URL as produced by `UIImage.toBase64()`.
    static let base64Image = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/"

    static func makeWireframe() -> RRWireframe {
        let wireframe = RRWireframe()
        wireframe.id = 42
        wireframe.posX = 16
        wireframe.posY = 120
        wireframe.width = 343
        wireframe.height = 44
        return wireframe
    }

    @Suite("toDict")
    struct ToDictTests {
        @Test("only produces the required geometry keys when nothing else is set")
        func onlyRequiredKeysWhenNothingSet() {
            let dict = RRWireframe().toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height"])
            #expect(dict["id"] as? Int == 0)
            #expect(dict["x"] as? Int == 0)
            #expect(dict["y"] as? Int == 0)
            #expect(dict["width"] as? Int == 0)
            #expect(dict["height"] as? Int == 0)
        }

        @Test("always includes the required geometry keys with their values")
        func includesRequiredKeys() {
            let dict = RRWireframeTest.makeWireframe().toDict()

            #expect(dict["id"] as? Int == 42)
            #expect(dict["x"] as? Int == 16)
            #expect(dict["y"] as? Int == 120)
            #expect(dict["width"] as? Int == 343)
            #expect(dict["height"] as? Int == 44)
            #expect(dict.count == 5)
        }

        @Test("includes all fields when everything is set")
        func includesAllFields() {
            let wireframe = RRWireframeTest.makeWireframe()
            let child = RRWireframe()
            child.id = 43
            child.type = "text"
            child.text = "Sign in"
            wireframe.childWireframes = [child]
            wireframe.type = "input"
            wireframe.inputType = "select"
            wireframe.text = "Country"
            wireframe.label = "Country"
            wireframe.value = "Austria"
            wireframe.base64 = RRWireframeTest.base64Image
            let style = RRStyle()
            style.color = "#000000"
            style.backgroundColor = "#FFFFFF"
            wireframe.style = style
            wireframe.disabled = false
            wireframe.checked = true
            wireframe.options = ["Austria", "Germany", "Portugal"]
            wireframe.max = 100

            let dict = wireframe.toDict()

            #expect(dict["id"] as? Int == 42)
            let children = dict["childWireframes"] as? [[String: Any]]
            #expect(children?.count == 1)
            #expect(children?.first?["id"] as? Int == 43)
            #expect(children?.first?["type"] as? String == "text")
            #expect(children?.first?["text"] as? String == "Sign in")
            #expect(dict["type"] as? String == "input")
            #expect(dict["inputType"] as? String == "select")
            #expect(dict["text"] as? String == "Country")
            #expect(dict["label"] as? String == "Country")
            #expect(dict["value"] as? String == "Austria")
            #expect(dict["base64"] as? String == RRWireframeTest.base64Image)
            let styleDict = dict["style"] as? [String: Any]
            #expect(styleDict?["color"] as? String == "#000000")
            #expect(styleDict?["backgroundColor"] as? String == "#FFFFFF")
            #expect(styleDict?.count == 2)
            #expect(dict["disabled"] as? Bool == false)
            #expect(dict["checked"] as? Bool == true)
            #expect(dict["options"] as? [String] == ["Austria", "Germany", "Portugal"])
            #expect(dict["max"] as? Int == 100)
            #expect(dict.count == 5 + 12)
        }

        @Test("a single optional field only produces its own key", arguments: [
            ("childWireframes", { (w: RRWireframe) in w.childWireframes = [] }, "[]"),
            ("type", { (w: RRWireframe) in w.type = "div" }, "div"),
            ("inputType", { (w: RRWireframe) in w.inputType = "text_area" }, "text_area"),
            ("text", { (w: RRWireframe) in w.text = "Welcome back" }, "Welcome back"),
            ("label", { (w: RRWireframe) in w.label = "Email" }, "Email"),
            ("value", { (w: RRWireframe) in w.value = "1" }, "1"),
            ("base64", { (w: RRWireframe) in w.base64 = RRWireframeTest.base64Image }, RRWireframeTest.base64Image),
            ("style", { (w: RRWireframe) in w.style = RRStyle() }, "[:]"),
            ("disabled", { (w: RRWireframe) in w.disabled = true }, "true"),
            ("checked", { (w: RRWireframe) in w.checked = true }, "true"),
            ("options", { (w: RRWireframe) in w.options = ["Small", "Large"] }, #"["Small", "Large"]"#),
            ("max", { (w: RRWireframe) in w.max = 1 }, "1"),
        ])
        func singleFieldOnlyProducesItsOwnKey(key: String, set: (RRWireframe) -> Void, expected: String) {
            let wireframe = RRWireframe()
            set(wireframe)

            let dict = wireframe.toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height", key])
            #expect(dict[key].map { String(describing: $0) } == expected)
            #expect(dict["id"] as? Int == 0)
        }

        @Test("omits keys for nil fields in a partially set wireframe")
        func omitsNilFields() {
            let wireframe = RRWireframeTest.makeWireframe()
            wireframe.type = "text"
            wireframe.text = "Add to cart"

            let dict = wireframe.toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height", "type", "text"])
            #expect(dict["id"] as? Int == 42)
            #expect(dict["x"] as? Int == 16)
            #expect(dict["y"] as? Int == 120)
            #expect(dict["width"] as? Int == 343)
            #expect(dict["height"] as? Int == 44)
            #expect(dict["type"] as? String == "text")
            #expect(dict["text"] as? String == "Add to cart")
            #expect(!dict.values.contains { $0 is NSNull })
        }

        @Test("keeps zero and false values")
        func keepsZeroAndFalseValues() {
            let wireframe = RRWireframe()
            wireframe.disabled = false
            wireframe.checked = false
            wireframe.max = 0
            wireframe.text = ""
            wireframe.value = 0
            wireframe.options = []

            let dict = wireframe.toDict()

            #expect(dict["disabled"] as? Bool == false)
            #expect(dict["checked"] as? Bool == false)
            #expect(dict["max"] as? Int == 0)
            #expect(dict["text"] as? String == "")
            #expect(dict["value"] as? Int == 0)
            #expect((dict["options"] as? [String])?.isEmpty == true)
            #expect(dict.count == 5 + 6)
        }

        @Test("keeps numeric and string values as-is")
        func keepsValueTypes() {
            let numeric = RRWireframe()
            numeric.value = 0.75
            let string = RRWireframe()
            string.value = "Hello"

            #expect(numeric.toDict()["value"] as? Double == 0.75)
            #expect(string.toDict()["value"] as? String == "Hello")
        }

        @Test("converts nested child wireframes to dictionaries")
        func convertsChildren() {
            let parent = RRWireframe()
            parent.type = "radio_group"
            let first = RRWireframe()
            first.id = 1
            first.type = "div"
            let second = RRWireframe()
            second.id = 2
            second.type = "div"
            second.checked = true
            parent.childWireframes = [first, second]

            let children = parent.toDict()["childWireframes"] as? [[String: Any]]

            #expect(children?.count == 2)
            #expect(children?[0]["id"] as? Int == 1)
            #expect(children?[0]["checked"] == nil)
            #expect(children?[1]["id"] as? Int == 2)
            #expect(children?[1]["checked"] as? Bool == true)
        }

        @Test("uses realistic wireframe types", arguments: ["text", "input", "image", "div", "radio_group", "screenshot"])
        func realisticTypes(type: String) {
            let wireframe = RRWireframeTest.makeWireframe()
            wireframe.type = type

            #expect(wireframe.toDict()["type"] as? String == type)
        }
    }
}
