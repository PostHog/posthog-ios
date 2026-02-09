//
//  PostHogPropertiesSerializationTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 09/02/2026.
//

import Foundation
@testable import PostHog
import Testing

// MARK: - Test Types

/// A simple Encodable struct for testing
private struct EncodableUser: Encodable {
    let name: String
    let age: Int
}

/// A simple Codable struct for testing
private struct CodableProduct: Codable {
    let id: String
    let price: Double
}

/// A non-Encodable class for testing
private class NonEncodableObject {
    let value: String

    init(value: String) {
        self.value = value
    }
}

/// A custom NSObject subclass for testing
private class CustomNSObject: NSObject {
    let identifier: String

    init(identifier: String) {
        self.identifier = identifier
        super.init()
    }
}

/// An enum that is Encodable
private enum EncodableStatus: String, Encodable {
    case active
    case inactive
}

/// An enum that is not Encodable
private enum NonEncodableStatus {
    case pending
    case completed
}

// MARK: - Test Suite

@Suite(.serialized)
struct PostHogPropertiesSerializationTests {
    // MARK: - Property Type Definitions

    /// Returns a dictionary with primitive types that should serialize correctly
    static func primitiveProperties() -> [String: Any] {
        [
            "string": "hello",
            "int": 42,
            "double": 3.14159,
            "float": Float(2.5),
            "bool_true": true,
            "bool_false": false,
            "int8": Int8(8),
            "int16": Int16(16),
            "int32": Int32(32),
            "int64": Int64(64),
            "uint": UInt(100),
            "uint8": UInt8(8),
            "uint16": UInt16(16),
            "uint32": UInt32(32),
            "uint64": UInt64(64),
        ]
    }

    /// Returns a dictionary with collection types
    static func collectionProperties() -> [String: Any] {
        [
            "array_strings": ["a", "b", "c"],
            "array_ints": [1, 2, 3],
            "array_mixed": [1, "two", 3.0] as [Any],
            "nested_dict": ["key": "value", "number": 42] as [String: Any],
            "empty_array": [] as [Any],
            "empty_dict": [:] as [String: Any],
        ]
    }

    /// Returns a dictionary with null/nil values
    static func nullableProperties() -> [String: Any] {
        [
            "null_value": NSNull(),
            "optional_string": Optional<String>.none as Any,
        ]
    }

    /// Returns a dictionary with Date objects - THIS WILL CRASH JSONSerialization
    static func dateProperties() -> [String: Any] {
        [
            "date_now": Date(),
            "date_past": Date(timeIntervalSince1970: 0),
            "date_future": Date(timeIntervalSinceNow: 86400),
        ]
    }

    /// Returns a dictionary with URL objects
    static func urlProperties() -> [String: Any] {
        [
            "url_https": URL(string: "https://posthog.com")!,
            "url_file": URL(fileURLWithPath: "/tmp/test.txt"),
        ]
    }

    /// Returns a dictionary with Data objects - THIS WILL CRASH JSONSerialization
    static func dataProperties() -> [String: Any] {
        [
            "data_utf8": "hello".data(using: .utf8)!,
            "data_empty": Data(),
        ]
    }

    /// Returns a dictionary with Encodable objects - NOT directly JSON serializable
    static func encodableProperties() -> [String: Any] {
        [
            "encodable_user": EncodableUser(name: "John", age: 30),
            "codable_product": CodableProduct(id: "123", price: 99.99),
            "encodable_enum": EncodableStatus.active,
        ]
    }

    /// Returns a dictionary with non-Encodable objects - THIS WILL CRASH JSONSerialization
    static func nonEncodableProperties() -> [String: Any] {
        [
            "non_encodable_object": NonEncodableObject(value: "test"),
            "custom_nsobject": CustomNSObject(identifier: "abc"),
            "non_encodable_enum": NonEncodableStatus.pending,
        ]
    }

    /// Returns a dictionary with nested problematic types
    static func nestedProblematicProperties() -> [String: Any] {
        [
            "nested_with_date": [
                "name": "test",
                "created_at": Date(),
            ] as [String: Any],
            "array_with_dates": [Date(), Date()] as [Any],
        ]
    }

    /// Returns a dictionary with UUID objects
    static func uuidProperties() -> [String: Any] {
        [
            "uuid": UUID(),
        ]
    }

    /// Returns a dictionary with Decimal objects
    static func decimalProperties() -> [String: Any] {
        [
            "decimal": Decimal(string: "123.456")!,
            "decimal_large": Decimal(string: "999999999999999999.999999999")!,
        ]
    }

    // MARK: - Base Test Class

    class BaseTestSuite {
        var server: MockPostHogServer

        init() {
            server = MockPostHogServer(version: 4)
            server.start()
        }

        deinit {
            server.stop()
        }

        func getSut(flushAt: Int = 1) -> PostHogSDK {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.flushAt = flushAt
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.personProfiles = .always
            config.preloadFeatureFlags = false

            deleteSafely(applicationSupportDirectoryURL())

            return PostHogSDK.with(config)
        }

        func getEvents() async throws -> [PostHogEvent] {
            try await getServerEvents(server)
        }
    }

    // MARK: - capture() tests

    @Suite("capture with properties")
    class CaptureWithPropertiesTests: BaseTestSuite {
        @Test("handles primitive properties")
        func handlesPrimitiveProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: primitiveProperties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "test_event")
            #expect(events.first?.properties["string"] as? String == "hello")
            #expect(events.first?.properties["int"] as? Int == 42)
            #expect(events.first?.properties["bool_true"] as? Bool == true)

            sut.reset()
            sut.close()
        }

        @Test("handles collection properties")
        func handlesCollectionProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: collectionProperties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.properties["array_strings"] as? [String] == ["a", "b", "c"])

            sut.reset()
            sut.close()
        }

        @Test("handles Date properties")
        func crashesWithDateProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: dateProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles Data properties")
        func crashesWithDataProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: dataProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable object properties")
        func crashesWithNonEncodableObjectProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: nonEncodableProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles nested Date properties")
        func crashesWithNestedDateProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: nestedProblematicProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles URL properties")
        func handlesURLProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: urlProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles UUID properties")
        func handlesUUIDProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: uuidProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles Decimal properties")
        func handlesDecimalProperties() async throws {
            let sut = getSut()

            sut.capture("test_event", properties: decimalProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - capture() with userProperties tests

    @Suite("capture with userProperties")
    class CaptureWithUserPropertiesTests: BaseTestSuite {
        @Test("handles Date in userProperties")
        func crashesWithDateInUserProperties() async throws {
            let sut = getSut()

            sut.capture(
                "test_event",
                properties: ["key": "value"],
                userProperties: dateProperties()
            )

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles Date in userPropertiesSetOnce")
        func crashesWithDateInUserPropertiesSetOnce() async throws {
            let sut = getSut()

            sut.capture(
                "test_event",
                properties: ["key": "value"],
                userProperties: nil,
                userPropertiesSetOnce: dateProperties()
            )

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable objects in userProperties")
        func crashesWithNonEncodableObjectsInUserProperties() async throws {
            let sut = getSut()

            sut.capture(
                "test_event",
                properties: nil,
                userProperties: nonEncodableProperties()
            )

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - screen() tests

    @Suite("screen with properties")
    class ScreenWithPropertiesTests: BaseTestSuite {
        @Test("handles primitive properties")
        func handlesPrimitiveProperties() async throws {
            let sut = getSut()

            sut.screen("TestScreen", properties: primitiveProperties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "$screen")

            sut.reset()
            sut.close()
        }

        @Test("handles Date properties")
        func crashesWithDateProperties() async throws {
            let sut = getSut()

            sut.screen("TestScreen", properties: dateProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable object properties")
        func crashesWithNonEncodableObjectProperties() async throws {
            let sut = getSut()

            sut.screen("TestScreen", properties: nonEncodableProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - identify() tests

    @Suite("identify with userProperties")
    class IdentifyWithUserPropertiesTests: BaseTestSuite {
        @Test("handles primitive userProperties")
        func handlesPrimitiveUserProperties() async throws {
            let sut = getSut()

            sut.identify("user123", userProperties: primitiveProperties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "$identify")

            sut.reset()
            sut.close()
        }

        @Test("handles Date in userProperties")
        func crashesWithDateInUserProperties() async throws {
            let sut = getSut()

            sut.identify("user123", userProperties: dateProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles Date in userPropertiesSetOnce")
        func crashesWithDateInUserPropertiesSetOnce() async throws {
            let sut = getSut()

            sut.identify(
                "user123",
                userProperties: nil,
                userPropertiesSetOnce: dateProperties()
            )

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable objects in userProperties")
        func crashesWithNonEncodableObjectsInUserProperties() async throws {
            let sut = getSut()

            sut.identify("user123", userProperties: nonEncodableProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles Encodable structs in userProperties")
        func crashesWithEncodableStructsInUserProperties() async throws {
            let sut = getSut()

            sut.identify("user123", userProperties: encodableProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - group() tests

    @Suite("group with groupProperties")
    class GroupWithGroupPropertiesTests: BaseTestSuite {
        @Test("handles primitive groupProperties")
        func handlesPrimitiveGroupProperties() async throws {
            let sut = getSut()

            sut.group(type: "company", key: "posthog", groupProperties: primitiveProperties())

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.event == "$groupidentify")

            sut.reset()
            sut.close()
        }

        @Test("handles Date in groupProperties")
        func crashesWithDateInGroupProperties() async throws {
            let sut = getSut()

            sut.group(type: "company", key: "posthog", groupProperties: dateProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable objects in groupProperties")
        func crashesWithNonEncodableObjectsInGroupProperties() async throws {
            let sut = getSut()

            sut.group(type: "company", key: "posthog", groupProperties: nonEncodableProperties())

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - register() tests

    @Suite("register with properties")
    class RegisterWithPropertiesTests: BaseTestSuite {
        @Test("handles primitive properties")
        func handlesPrimitiveProperties() async throws {
            let sut = getSut()

            sut.register(primitiveProperties())
            sut.capture("test_event")

            let events = try await getEvents()
            #expect(events.count == 1)
            #expect(events.first?.properties["string"] as? String == "hello")

            sut.reset()
            sut.close()
        }

        @Test("handles Date properties")
        func crashesWithDateProperties() async throws {
            let sut = getSut()

            sut.register(dateProperties())
            sut.capture("test_event")

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable object properties")
        func crashesWithNonEncodableObjectProperties() async throws {
            let sut = getSut()

            sut.register(nonEncodableProperties())
            sut.capture("test_event")

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - setPersonProperties() tests

    @Suite("setPersonProperties")
    class SetPersonPropertiesTests: BaseTestSuite {
        @Test("handles primitive properties")
        func handlesPrimitiveProperties() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: primitiveProperties())

            let events = try await getEvents()
            #expect(events.count == 2)
            #expect(events.last?.event == "$set")

            sut.reset()
            sut.close()
        }

        @Test("handles Date in userPropertiesToSet")
        func crashesWithDateInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: dateProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles Date in userPropertiesToSetOnce")
        func crashesWithDateInUserPropertiesToSetOnce() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(
                userPropertiesToSet: nil,
                userPropertiesToSetOnce: dateProperties()
            )

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles Data in userPropertiesToSet")
        func crashesWithDataInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: dataProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles URL in userPropertiesToSet")
        func crashesWithURLInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: urlProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles UUID in userPropertiesToSet")
        func crashesWithUUIDInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: uuidProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable object in userPropertiesToSet")
        func crashesWithNonEncodableInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: nonEncodableProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles Encodable struct in userPropertiesToSet")
        func crashesWithEncodableStructInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: encodableProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }

        @Test("handles nested Date in userPropertiesToSet")
        func crashesWithNestedDateInUserPropertiesToSet() async throws {
            let sut = getSut(flushAt: 2)

            sut.identify("user123")
            sut.setPersonProperties(userPropertiesToSet: nestedProblematicProperties())

            let events = try await getEvents()
            #expect(events.count == 2)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - setPersonPropertiesForFlags() tests

    @Suite("setPersonPropertiesForFlags")
    class SetPersonPropertiesForFlagsTests: BaseTestSuite {
        @Test("handles primitive properties")
        func handlesPrimitiveProperties() async throws {
            let sut = getSut()

            sut.setPersonPropertiesForFlags(primitiveProperties(), reloadFeatureFlags: false)

            sut.reset()
            sut.close()
        }

        @Test("handles Date properties")
        func crashesWithDateProperties() async throws {
            let sut = getSut()

            sut.setPersonPropertiesForFlags(dateProperties(), reloadFeatureFlags: false)

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable object properties")
        func crashesWithNonEncodableObjectProperties() async throws {
            let sut = getSut()

            sut.setPersonPropertiesForFlags(nonEncodableProperties(), reloadFeatureFlags: false)

            sut.reset()
            sut.close()
        }
    }

    // MARK: - setGroupPropertiesForFlags() tests

    @Suite("setGroupPropertiesForFlags")
    class SetGroupPropertiesForFlagsTests: BaseTestSuite {
        @Test("handles primitive properties")
        func handlesPrimitiveProperties() async throws {
            let sut = getSut()

            sut.setGroupPropertiesForFlags(
                "company",
                properties: primitiveProperties(),
                reloadFeatureFlags: false
            )

            sut.reset()
            sut.close()
        }

        @Test("handles Date properties")
        func crashesWithDateProperties() async throws {
            let sut = getSut()

            sut.setGroupPropertiesForFlags(
                "company",
                properties: dateProperties(),
                reloadFeatureFlags: false
            )

            sut.reset()
            sut.close()
        }

        @Test("handles non-Encodable object properties")
        func crashesWithNonEncodableObjectProperties() async throws {
            let sut = getSut()

            sut.setGroupPropertiesForFlags(
                "company",
                properties: nonEncodableProperties(),
                reloadFeatureFlags: false
            )

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

        @Test("handles array containing Date objects")
        func handlesArrayContainingDateObjects() async throws {
            let sut = getSut()

            let arrayWithDates: [String: Any] = [
                "dates": [Date(), Date(), Date()],
            ]

            sut.capture("test_event", properties: arrayWithDates)

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }

        @Test("handles mixed array with Date and primitives")
        func handlesMixedArrayWithDateAndPrimitives() async throws {
            let sut = getSut()

            let mixedArray: [String: Any] = [
                "mixed": ["string", 42, Date(), true] as [Any],
            ]

            sut.capture("test_event", properties: mixedArray)

            let events = try await getEvents()
            #expect(events.count == 1)

            sut.reset()
            sut.close()
        }
    }
}
