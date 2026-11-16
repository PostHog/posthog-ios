//
//  NetworkSampleTest.swift
//  PostHogTests
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("NetworkSample Tests")
    struct NetworkSampleTest {
        static let timeOrigin = Date(timeIntervalSince1970: 1_700_000_000)

        @Suite("toDict")
        struct ToDictTests {
            @Test("only produces the required keys when nothing else is set")
            func onlyRequiredKeysWhenNothingSet() {
                let sample = NetworkSample(sessionId: "session-1", timeOrigin: NetworkSampleTest.timeOrigin)

                let dict = sample.toDict()

                #expect(Set(dict.keys) == ["timestamp", "entryType", "initiatorType"])
                #expect(dict["timestamp"] as? Int64 == 1_700_000_000_000)
                #expect(dict["entryType"] as? String == "resource")
                #expect(dict["initiatorType"] as? String == "fetch")
            }

            @Test("includes all fields when everything is set")
            func includesAllFields() {
                var sample = NetworkSample(
                    sessionId: "session-1",
                    timeOrigin: NetworkSampleTest.timeOrigin,
                    url: "https://api.example.com/v1/items?page=2"
                )
                sample.responseStatus = 200
                sample.httpMethod = "GET"
                sample.duration = 184
                sample.decodedBodySize = 5120

                let dict = sample.toDict()

                #expect(dict["timestamp"] as? Int64 == 1_700_000_000_000)
                #expect(dict["entryType"] as? String == "resource")
                #expect(dict["initiatorType"] as? String == "fetch")
                #expect(dict["name"] as? String == "https://api.example.com/v1/items?page=2")
                #expect(dict["responseStatus"] as? Int == 200)
                #expect(dict["method"] as? String == "GET")
                #expect(dict["duration"] as? Int64 == 184)
                #expect(dict["transferSize"] as? Int64 == 5120)
                #expect(dict.count == 8)
            }

            @Test("a single optional field only produces its own key", arguments: [
                ("name", { (s: inout NetworkSample) in s.name = "https://api.example.com/v1/login" }, "https://api.example.com/v1/login"),
                ("responseStatus", { (s: inout NetworkSample) in s.responseStatus = 404 }, "404"),
                ("method", { (s: inout NetworkSample) in s.httpMethod = "POST" }, "POST"),
                ("duration", { (s: inout NetworkSample) in s.duration = 1250 }, "1250"),
                ("transferSize", { (s: inout NetworkSample) in s.decodedBodySize = 2048 }, "2048"),
            ])
            func singleFieldOnlyProducesItsOwnKey(key: String, set: (inout NetworkSample) -> Void, expected: String) {
                var sample = NetworkSample(sessionId: "session-1", timeOrigin: NetworkSampleTest.timeOrigin)
                set(&sample)

                let dict = sample.toDict()

                #expect(Set(dict.keys) == ["timestamp", "entryType", "initiatorType", key])
                #expect(dict[key].map { String(describing: $0) } == expected)
                #expect(dict["timestamp"] as? Int64 == 1_700_000_000_000)
                #expect(dict["entryType"] as? String == "resource")
                #expect(dict["initiatorType"] as? String == "fetch")
            }

            @Test("omits keys for nil fields in a partially set sample")
            func omitsNilFields() {
                var sample = NetworkSample(
                    sessionId: "session-1",
                    timeOrigin: NetworkSampleTest.timeOrigin,
                    url: "https://api.example.com/v1/items"
                )
                sample.httpMethod = "POST"
                sample.responseStatus = 404

                let dict = sample.toDict()

                #expect(Set(dict.keys) == ["timestamp", "entryType", "initiatorType", "name", "method", "responseStatus"])
                #expect(dict["name"] as? String == "https://api.example.com/v1/items")
                #expect(dict["method"] as? String == "POST")
                #expect(dict["responseStatus"] as? Int == 404)
                #expect(!dict.values.contains { $0 is NSNull })
            }

            @Test("keeps zero values")
            func keepsZeroValues() {
                var sample = NetworkSample(sessionId: "session-1", timeOrigin: NetworkSampleTest.timeOrigin)
                sample.responseStatus = 0
                sample.duration = 0
                sample.decodedBodySize = 0

                let dict = sample.toDict()

                #expect(dict["responseStatus"] as? Int == 0)
                #expect(dict["duration"] as? Int64 == 0)
                #expect(dict["transferSize"] as? Int64 == 0)
                #expect(dict.count == 6)
            }

            @Test("maps httpMethod to method and decodedBodySize to transferSize")
            func renamesKeys() {
                var sample = NetworkSample(sessionId: "session-1", timeOrigin: NetworkSampleTest.timeOrigin)
                sample.httpMethod = "POST"
                sample.decodedBodySize = 77

                let dict = sample.toDict()

                #expect(!dict.keys.contains("httpMethod"))
                #expect(!dict.keys.contains("decodedBodySize"))
                #expect(dict["method"] as? String == "POST")
                #expect(dict["transferSize"] as? Int64 == 77)
            }
        }
    }
#endif
