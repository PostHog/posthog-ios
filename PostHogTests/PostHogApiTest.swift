//
//  PostHogApiTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 29/01/2025.
//

import Foundation
import OHHTTPStubs
@testable import PostHog
import Testing

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

        func testFlagsEndpoint(forHost host: String) async throws {
            let sut = getSut(host: host)
            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, _ in
                    completion(data)
                }
            }

            #expect(try #require(resp)["errorsWhileComputingFlags"] as! Bool == false)
        }

        func testFlagsDoesNotRetryHTTPStatus(_ statusCode: Int) async throws {
            server.reset(flagsCount: 1)
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: ["error": "server error"], statusCode: Int32(statusCode), headers: nil)
            }

            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost")
            config.featureFlagRequestMaxRetries = 1
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, error in
                    completion((data, error))
                }
            }

            try await Task.sleep(nanoseconds: 50_000_000)

            #expect(resp.0 == nil)
            #expect(resp.1 != nil)
            #expect(server.flagsRequests.count == 1)
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
            PostHogApi(PostHogConfig(projectToken: "test_project_token", host: host))
        }
    }

    @Suite("Test batch endpoint with different host paths")
    class TestBatchEndpoint: BaseTestSuite {
        @Test("with host containing no path")
        func hostWithNoPath() async throws {
            try await testBatchEndpoint(forHost: "http://localhost")
        }

        @Test("with host containing no path and trailing slash")
        func hostWithNoPathAndTrailingSlash() async throws {
            try await testBatchEndpoint(forHost: "http://localhost/")
        }

        @Test("with host containing path")
        func hostWithPath() async throws {
            try await testBatchEndpoint(forHost: "http://localhost/api/v1")
        }

        @Test("with host containing path and trailing slash")
        func hostWithPathAndTrailingSlash() async throws {
            try await testBatchEndpoint(forHost: "http://localhost/api/v1/")
        }

        @Test("with host containing port number")
        func hostWithPortNumber() async throws {
            try await testBatchEndpoint(forHost: "http://localhost:9000")
        }

        @Test("with host containing port number and path")
        func hostWithPortNumberAndPath() async throws {
            try await testBatchEndpoint(forHost: "http://localhost:9000/api/v1")
        }

        @Test("with host containing port number, path and trailing slash")
        func hostWithPortNumberAndTrailingSlash() async throws {
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

    /// Guards the per-request Content-Encoding policy: upload endpoints
    /// declare `gzip`, /flags does not. A regression that re-added
    /// session-level gzip would silently mis-label /flags on the wire.
    @Suite("Content-Encoding header per endpoint")
    class TestContentEncodingHeader: BaseTestSuite {
        @Test("/batch declares gzip Content-Encoding")
        func batchDeclaresGzip() async throws {
            let sut = getSut(host: "http://localhost")
            _ = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }
            let request = try #require(server.batchRequests.first)
            #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        }

        @Test("/s declares gzip Content-Encoding")
        func snapshotDeclaresGzip() async throws {
            let sut = getSut(host: "http://localhost")
            _ = await getApiResponse { completion in
                sut.snapshot(events: [], completion: completion)
            }
            let request = try #require(server.snapshotRequests.first)
            #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        }

        @Test("/i/v1/logs declares gzip Content-Encoding")
        func logsDeclaresGzip() async throws {
            let sut = getSut(host: "http://localhost")
            _ = await getApiResponse { completion in
                sut.logs(payload: ["resourceLogs": []], completion: completion)
            }
            let request = try #require(server.logsRequests.first)
            #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        }

        @Test("/batch falls back to uncompressed when gzip fails")
        func batchFallsBackToUncompressedWhenGzipFails() async throws {
            let originalGzipData = PostHogApi.gzipData
            PostHogApi.gzipData = { _ in throw NSError(domain: "PostHogApiTests", code: 1) }
            defer { PostHogApi.gzipData = originalGzipData }

            let sut = getSut(host: "http://localhost")
            _ = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }
            let request = try #require(server.batchRequests.first)
            #expect(request.value(forHTTPHeaderField: "Content-Encoding") == nil)
            #expect(server.parseRequest(request, gzip: false)?["batch"] != nil)
        }

        @Test("/flags does not declare Content-Encoding")
        func flagsDoesNotDeclareGzip() async throws {
            let sut = getSut(host: "http://localhost")
            _ = await getApiResponse { completion in
                sut.flags(distinctId: "x", anonymousId: nil, groups: [:], personProperties: [:]) { data, _ in
                    completion(data)
                }
            }
            let request = try #require(server.flagsRequests.first)
            #expect(request.value(forHTTPHeaderField: "Content-Encoding") == nil)
        }
    }

    /// Custom `config.requestHeaders` (e.g. an Authorization header for a reverse
    /// proxy) must be attached to every request the SDK sends.
    @Suite("Custom request headers")
    class TestCustomRequestHeaders: BaseTestSuite {
        func getSut(host: String, requestHeaders: [String: String]?) -> PostHogApi {
            let config = PostHogConfig(projectToken: "test_project_token", host: host)
            config.requestHeaders = requestHeaders
            return PostHogApi(config)
        }

        @Test("attaches custom headers to /batch requests")
        func attachesToBatch() async throws {
            let sut = getSut(host: "http://localhost", requestHeaders: ["Authorization": "Bearer test-jwt"])
            _ = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }
            let request = try #require(server.batchRequests.first)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-jwt")
        }

        @Test("attaches custom headers to /flags requests")
        func attachesToFlags() async throws {
            let sut = getSut(host: "http://localhost", requestHeaders: ["Authorization": "Bearer test-jwt"])
            _ = await getApiResponse { completion in
                sut.flags(distinctId: "x", anonymousId: nil, groups: [:], personProperties: [:]) { data, _ in
                    completion(data)
                }
            }
            let request = try #require(server.flagsRequests.first)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-jwt")
        }

        @Test("does not attach an Authorization header when none is configured")
        func noHeaderWhenUnset() async throws {
            let sut = getSut(host: "http://localhost", requestHeaders: nil)
            _ = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }
            let request = try #require(server.batchRequests.first)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Suite("Test flags endpoint with different host paths")
    class TestFlagsEndpoint: BaseTestSuite {
        @Test("feature flag retry delay starts at 300ms and doubles")
        func featureFlagRetryDelayStartsAt300msAndDoubles() {
            #expect(abs(PostHogApi.featureFlagsRetryDelay(forFailedAttempt: 1) - 0.3) < 0.0001)
            #expect(abs(PostHogApi.featureFlagsRetryDelay(forFailedAttempt: 2) - 0.6) < 0.0001)
            #expect(abs(PostHogApi.featureFlagsRetryDelay(forFailedAttempt: 3) - 1.2) < 0.0001)
        }

        @Test("retries transient URLSession errors before returning flags")
        func retriesURLSessionErrors() async throws {
            server.reset(flagsCount: 2)

            var requestCount = 0
            let requestCountLock = NSLock()
            let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
            server.flagsResponseHandler = { _ in
                requestCountLock.lock()
                requestCount += 1
                let currentRequestCount = requestCount
                requestCountLock.unlock()

                if currentRequestCount == 1 {
                    return HTTPStubsResponse(error: networkError)
                }

                return HTTPStubsResponse(jsonObject: ["errorsWhileComputingFlags": false], statusCode: 200, headers: nil)
            }

            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost")
            config.featureFlagRequestMaxRetries = 1
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, error in
                    completion((data, error))
                }
            }

            #expect(try #require(resp.0)["errorsWhileComputingFlags"] as! Bool == false)
            #expect(resp.1 == nil)
            #expect(server.flagsRequests.count == 2)
        }

        @Test("does not retry when feature flag request max retries is zero")
        func doesNotRetryWhenFeatureFlagRequestMaxRetriesIsZero() async throws {
            server.reset(flagsCount: 1)
            let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(error: networkError)
            }

            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost")
            config.featureFlagRequestMaxRetries = 0
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, error in
                    completion((data, error))
                }
            }

            try await Task.sleep(nanoseconds: 50_000_000)

            #expect(resp.0 == nil)
            #expect(resp.1 != nil)
            #expect(server.flagsRequests.count == 1)
        }

        @Test("stops retrying transient URLSession errors after feature flag request max retries")
        func stopsRetryingTransientURLSessionErrorsAfterFeatureFlagRequestMaxRetries() async throws {
            server.reset(flagsCount: 3)
            let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(error: networkError)
            }

            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost")
            config.featureFlagRequestMaxRetries = 2
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, error in
                    completion((data, error))
                }
            }

            #expect(resp.0 == nil)
            #expect(resp.1 != nil)
            #expect(server.flagsRequests.count == 3)
        }

        @Test("does not retry non-transient URLSession errors", arguments: [NSURLErrorCannotConnectToHost, NSURLErrorCancelled])
        func doesNotRetryNonTransientURLSessionErrors(errorCode: Int) async throws {
            server.reset(flagsCount: 1)
            let networkError = NSError(domain: NSURLErrorDomain, code: errorCode, userInfo: nil)
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(error: networkError)
            }

            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost")
            config.featureFlagRequestMaxRetries = 1
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, error in
                    completion((data, error))
                }
            }

            try await Task.sleep(nanoseconds: 50_000_000)

            #expect(resp.0 == nil)
            #expect(resp.1 != nil)
            #expect(server.flagsRequests.count == 1)
        }

        @Test("does not retry HTTP error responses", arguments: [408, 429, 500])
        func doesNotRetryHTTPErrorResponses(statusCode: Int) async throws {
            try await testFlagsDoesNotRetryHTTPStatus(statusCode)
        }

        @Test("with host containing no path")
        func testHostWithNoPath() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost")
        }

        @Test("with host containing no path and trailing slash")
        func testHostWithNoPathAndTrailingSlash() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost/")
        }

        @Test("with host containing path")
        func testHostWithPath() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost/api/v1")
        }

        @Test("with host containing path and trailing slash")
        func testHostWithPathAndTrailingSlash() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost/api/v1/")
        }

        @Test("with host containing port number")
        func testHostWithPortNumber() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost:9000")
        }

        @Test("with host containing port number and path")
        func testHostWithPortNumberAndPath() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost:9000/api/v1")
        }

        @Test("with host containing port number, path and trailing slash")
        func testHostWithPortNumberAndTrailingSlash() async throws {
            try await testFlagsEndpoint(forHost: "http://localhost:9000/api/v1/")
        }
    }
}
