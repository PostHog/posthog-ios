//
//  PostHogPropertiesSerializationTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 09/02/2026.
//

import CoreGraphics
import Foundation
@testable import PostHog
import Testing

struct PropertyTestCase: CustomTestStringConvertible, Sendable {
    let name: String
    let properties: @Sendable () -> [String: Any]

    var testDescription: String { name }

    init(_ name: String, _ properties: @Sendable @escaping () -> [String: Any]) {
        self.name = name
        self.properties = properties
    }
}

// MARK: - Test Suite

@Suite(.serialized)
struct PostHogPropertiesSerializationTests {
    // MARK: - Test Payloads

    static let propertyPayloads: [PropertyTestCase] = [
        // Valid JSON types. Should not cause any issues
        PropertyTestCase("primitives") { ["string": "hello", "int": 42, "double": 3.14, "bool": true] },
        PropertyTestCase("collections") { ["array": ["a", "b"], "dict": ["key": "value"] as [String: Any]] },
        PropertyTestCase("nullables") { ["null_value": NSNull()] },

        // Invalid JSON types. Will crash if not sanitized
        PropertyTestCase("date") { ["date": Date()] },
        PropertyTestCase("url") { ["url": URL(string: "https://posthog.com")!] },
        PropertyTestCase("data") { ["data": "hello".data(using: .utf8)!] },
        PropertyTestCase("encodableStruct") { ["user": EncodableUser(name: "John", age: 30)] },
        PropertyTestCase("nonEncodableObject") { ["object": NonEncodableObject(value: "test")] },
        PropertyTestCase("nestedWithDate") { ["nested": ["date": Date()] as [String: Any]] },
        PropertyTestCase("uuid") { ["uuid": UUID()] },
        PropertyTestCase("decimal") { ["decimal": Decimal(string: "123.456")!] },

        // Special numeric values
        PropertyTestCase("doubleInfinity") { ["value": Double.infinity] },
        PropertyTestCase("doubleNaN") { ["value": Double.nan] },
        PropertyTestCase("floatInfinity") { ["value": Float.infinity] },

        // Core Graphics types (common in iOS)
        PropertyTestCase("cgFloat") { ["value": CGFloat(3.14)] },
        PropertyTestCase("cgPoint") { ["point": CGPoint(x: 10, y: 20)] },
        PropertyTestCase("cgSize") { ["size": CGSize(width: 100, height: 200)] },
        PropertyTestCase("cgRect") { ["rect": CGRect(x: 0, y: 0, width: 100, height: 100)] },

        // Other Foundation types
        PropertyTestCase("nsError") { ["error": NSError(domain: "test", code: 1)] },
        PropertyTestCase("nsRange") { ["range": NSRange(location: 0, length: 10)] },
        PropertyTestCase("locale") { ["locale": Locale.current] },
        PropertyTestCase("timeZone") { ["timezone": TimeZone.current] },
        PropertyTestCase("calendar") { ["calendar": Calendar.current] },
        PropertyTestCase("indexPath") { ["indexPath": IndexPath(item: 0, section: 0)] },

        // Mixed valid and invalid types
        PropertyTestCase("mixedTypes") {
            [
                "validString": "hello",
                "validInt": 42,
                "invalidDate": Date(),
                "validBool": true,
                "invalidURL": URL(string: "https://posthog.com")!,
            ]
        },
        PropertyTestCase("nestedMixed") {
            [
                "level1": [
                    "valid": "string",
                    "invalid": Date(),
                ] as [String: Any],
            ]
        },
        PropertyTestCase("arrayWithMixedTypes") {
            ["items": ["valid", 42, Date(), true] as [Any]]
        },
    ]

    // MARK: - Base Test Class

    class BaseTestSuite: PostHogSDKBaseTest {
        init() {
            super.init(serverVersion: 4)
        }

        func getSut(flushAt: Int = 1) -> PostHogSDK {
            server.reset(batchCount: flushAt)
            let config = makeConfig()
            config.flushAt = flushAt
            config.personProfiles = .always
            return makeSDK(config: config)
        }

        func getEvents() async throws -> [PostHogEvent] {
            try await getServerEvents(server)
        }
    }

    // MARK: - capture() with properties

    @Suite("capture with properties")
    class CapturePropertiesTests: BaseTestSuite {
        @Test("capture with property type", arguments: propertyPayloads)
        func captureWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.capture("test_event", properties: payload.properties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "test_event")

            sut.reset()
            sut.close()
        }
    }

    // MARK: - screen() with properties

    @Suite("screen with properties")
    class ScreenPropertiesTests: BaseTestSuite {
        @Test("screen with property type", arguments: propertyPayloads)
        func screenWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.screen("TestScreen", properties: payload.properties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "$screen")

            sut.reset()
            sut.close()
        }
    }

    // MARK: - identify() with userProperties

    @Suite("identify with userProperties")
    class IdentifyPropertiesTests: BaseTestSuite {
        @Test("identify with property type", arguments: propertyPayloads)
        func identifyWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.identify("user123", userProperties: payload.properties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "$identify")

            sut.reset()
            sut.close()
        }
    }

    // MARK: - group() with groupProperties

    @Suite("group with groupProperties")
    class GroupPropertiesTests: BaseTestSuite {
        @Test("group with property type", arguments: propertyPayloads)
        func groupWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.group(type: "company", key: "posthog", groupProperties: payload.properties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "$groupidentify")

            sut.reset()
            sut.close()
        }
    }

    // MARK: - register() with properties

    @Suite("register with properties")
    class RegisterPropertiesTests: BaseTestSuite {
        @Test("register with property type", arguments: propertyPayloads)
        func registerWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.register(payload.properties())
            sut.capture("test_event")

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - setPersonProperties()

    @Suite("setPersonProperties")
    class SetPersonPropertiesTests: BaseTestSuite {
        @Test("setPersonProperties with property type", arguments: propertyPayloads)
        func setPersonPropertiesWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: payload.properties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - setPersonPropertiesForFlags()

    @Suite("setPersonPropertiesForFlags")
    class SetPersonPropertiesForFlagsTests: BaseTestSuite {
        @Test("setPersonPropertiesForFlags with property type", arguments: propertyPayloads)
        func setPersonPropertiesForFlagsWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.setPersonPropertiesForFlags(payload.properties(), reloadFeatureFlags: false)

            // No-crash test: verifies non-JSON-serializable types don't crash

            sut.reset()
            sut.close()
        }
    }

    // MARK: - setGroupPropertiesForFlags()

    @Suite("setGroupPropertiesForFlags")
    class SetGroupPropertiesForFlagsTests: BaseTestSuite {
        @Test("setGroupPropertiesForFlags with property type", arguments: propertyPayloads)
        func setGroupPropertiesForFlagsWithPropertyType(_ payload: PropertyTestCase) async throws {
            let sut = getSut()

            sut.setGroupPropertiesForFlags("company", properties: payload.properties(), reloadFeatureFlags: false)

            // No-crash test: verifies non-JSON-serializable types don't crash

            sut.reset()
            sut.close()
        }
    }

    // MARK: - Edge cases

    @Suite("edge cases")
    class EdgeCasesTests: BaseTestSuite {
        @Test("handles empty properties")
        func handlesEmptyProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: [:])

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles nil properties")
        func handlesNilProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: nil)

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles deeply nested structures with Date")
        func handlesDeeplyNestedStructuresWithDate() async throws {
            let sut = getSut()

            let deeplyNested: [String: Any] = [
                "level1": [
                    "level2": [
                        "level3": [
                            "date": Date(),
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ]

            sut.capture("test_event", properties: deeplyNested)

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }
}

// MARK: - Test Types

private struct EncodableUser: Encodable {
    let name: String
    let age: Int
}

private class NonEncodableObject {
    let value: String
    init(value: String) {
        self.value = value
    }
}

private class CustomNSObject: NSObject {
    let identifier: String
    init(identifier: String) {
        self.identifier = identifier
        super.init()
    }
}

private enum EncodableStatus: String, Encodable {
    case active
    case inactive
}
