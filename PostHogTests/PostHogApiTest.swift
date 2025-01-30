//
//  PostHogApiTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 29/01/2025.
//

import Foundation
import Testing

@testable import PostHog

@Suite(.serialized)
enum PostHogApiTests {
    class BaseTestSuite {
        var server: MockPostHogServer!

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        func getApiResponse<T>(
            apiCall: @escaping (@escaping (T) -> Void) -> Void
        ) async -> T {
            await withCheckedContinuation { continuation in
                apiCall { resp in
                    continuation.resume(returning: resp)
                }
            }
        }
    }

    @Suite("Test batch endpoint with different host paths")
    class TestBatchEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/api/v1")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }

            #expect(resp.statusCode == 200)
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/api/v1/")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }
    }

    @Suite("Test snapshot endpoint with different host paths")
    class TestSnapshotEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.snapshot(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.snapshot(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/api/v1")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.snapshot(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/api/v1/")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.snapshot(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }
    }

    @Suite("Test decide endpoint with different host paths")
    class TestDecideEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.decide(distinctId: "", anonymousId: "", groups: [:]) { data, _ in
                    completion(data)
                }
            }

            #expect(try #require(resp)["errorsWhileComputingFlags"] as! Bool == false)
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.decide(distinctId: "", anonymousId: "", groups: [:]) { data, _ in
                    completion(data)
                }
            }

            #expect(try #require(resp)["errorsWhileComputingFlags"] as! Bool == false)
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/api/v1")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.decide(distinctId: "", anonymousId: "", groups: [:]) { data, _ in
                    completion(data)
                }
            }

            #expect(try #require(resp)["errorsWhileComputingFlags"] as! Bool == false)
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            let config = PostHogConfig(apiKey: "test_key", host: "http://localhost/api/v1/")
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.decide(distinctId: "", anonymousId: "", groups: [:]) { data, _ in
                    completion(data)
                }
            }

            #expect(try #require(resp)["errorsWhileComputingFlags"] as! Bool == false)
        }
    }
}
