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
            server = nil
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

        func testSnapshotEndpoint(forHost host: String) async throws {
            let sut = getSut(host: host)
            let resp = await getApiResponse { completion in
                sut.snapshot(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        func testDecideEndpoint(forHost host: String) async throws {
            let sut = getSut(host: host)
            let resp = await getApiResponse { completion in
                sut.decide(distinctId: "", anonymousId: "", groups: [:]) { data, _ in
                    completion(data)
                }
            }

            #expect(try #require(resp)["errorsWhileComputingFlags"] as! Bool == false)
        }

        func testBatchEndpoint(forHost host: String) async throws {
            let sut = getSut(host: host)
            let resp = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }

            #expect(resp.error == nil)
            #expect(resp.statusCode == 200)
        }

        func getSut(host: String) -> PostHogApi {
            PostHogApi(PostHogConfig(apiKey: "123", host: host))
        }
    }

    @Suite("Test batch endpoint with different host paths")
    class TestBatchEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            try await testBatchEndpoint(forHost: "http://localhost")
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            try await testBatchEndpoint(forHost: "http://localhost/")
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            try await testBatchEndpoint(forHost: "http://localhost/api/v1")
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            try await testBatchEndpoint(forHost: "http://localhost/api/v1/")
        }

        @Test("with host containing port number")
        func testHostWithPortNumber() async throws {
            try await testBatchEndpoint(forHost: "http://localhost:9000")
        }

        @Test("with host containing port number and path")
        func testHostWithPortNumberAndPath() async throws {
            try await testBatchEndpoint(forHost: "http://localhost:9000/api/v1")
        }

        @Test("with host containing port number, path and trailing slash")
        func testHostWithPortNumberAndTrailingSlash() async throws {
            try await testBatchEndpoint(forHost: "http://localhost:9000/api/v1/")
        }
    }

    @Suite("Test snapshot endpoint with different host paths")
    class TestSnapshotEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost")
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost/")
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost/api/v1")
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost/api/v1/")
        }

        @Test("with host containing port number")
        func testHostWithPortNumber() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost:9000")
        }

        @Test("with host containing port number and path")
        func testHostWithPortNumberAndPath() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost:9000/api/v1")
        }

        @Test("with host containing port number, path and trailing slash")
        func testHostWithPortNumberAndTrailingSlash() async throws {
            try await testSnapshotEndpoint(forHost: "http://localhost:9000/api/v1/")
        }
    }

    @Suite("Test decide endpoint with different host paths")
    class TestDecideEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            try await testDecideEndpoint(forHost: "http://localhost")
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            try await testDecideEndpoint(forHost: "http://localhost/")
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            try await testDecideEndpoint(forHost: "http://localhost/api/v1")
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            try await testDecideEndpoint(forHost: "http://localhost/api/v1/")
        }

        @Test("with host containing port number")
        func testHostWithPortNumber() async throws {
            try await testDecideEndpoint(forHost: "http://localhost:9000")
        }

        @Test("with host containing port number and path")
        func testHostWithPortNumberAndPath() async throws {
            try await testDecideEndpoint(forHost: "http://localhost:9000/api/v1")
        }

        @Test("with host containing port number, path and trailing slash")
        func testHostWithPortNumberAndTrailingSlash() async throws {
            try await testDecideEndpoint(forHost: "http://localhost:9000/api/v1/")
        }
    }
}
