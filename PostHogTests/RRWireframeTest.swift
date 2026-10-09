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

        @Test("a single optional field only produces its own key", arguments: [
            ("type", { (w: RRWireframe) in w.type = "screenshot" }, "screenshot"),
            ("base64", { (w: RRWireframe) in w.base64 = RRWireframeTest.base64Image }, RRWireframeTest.base64Image),
        ])
        func singleFieldOnlyProducesItsOwnKey(key: String, set: (RRWireframe) -> Void, expected: String) {
            let wireframe = RRWireframe()
            set(wireframe)

            let dict = wireframe.toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height", key])
            #expect(dict[key].map { String(describing: $0) } == expected)
            #expect(dict["id"] as? Int == 0)
        }

        @Test("includes the screenshot type and image")
        func includesScreenshotFields() {
            let wireframe = RRWireframeTest.makeWireframe()
            wireframe.type = "screenshot"
            wireframe.base64 = RRWireframeTest.base64Image

            let dict = wireframe.toDict()

            #expect(Set(dict.keys) == ["id", "x", "y", "width", "height", "type", "base64"])
            #expect(dict["type"] as? String == "screenshot")
            #expect(dict["base64"] as? String == RRWireframeTest.base64Image)
            #expect(!dict.values.contains { $0 is NSNull })
        }
    }
}
