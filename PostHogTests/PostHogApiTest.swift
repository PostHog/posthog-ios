//
//  PostHogApiTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 29/01/2025.
//

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
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

        @Test("does not let custom headers override SDK-managed headers")
        func doesNotOverrideSDKManagedHeaders() async throws {
            let sut = getSut(host: "http://localhost", requestHeaders: ["content-type": "text/plain", "User-Agent": "evil"])
            _ = await getApiResponse { completion in
                sut.batch(events: [], completion: completion)
            }
            let request = try #require(server.batchRequests.first)
            #expect(request.value(forHTTPHeaderField: "Content-Type") != "text/plain")
            #expect(request.value(forHTTPHeaderField: "User-Agent") != "evil")
        }
    }

    @Suite("Custom request headers host scoping", .serialized)
    final class TestCustomRequestHeadersHostScoping {
        init() {
            HTTPStubs.removeAllStubs()
        }
        deinit { HTTPStubs.removeAllStubs() }

        @Test("does not send custom headers to the rewritten static-config host")
        func skipsRewrittenConfigHost() async throws {
            let captured = CapturedRequestBox()
            stub(condition: isHost("us-assets.i.posthog.com")) { request in
                captured.set(request)
                return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
            }
            let config = PostHogConfig(projectToken: "test_project_token", host: "https://us.i.posthog.com")
            config.requestHeaders = ["Authorization": "Bearer test-jwt"]
            let sut = PostHogApi(config)

            await withCheckedContinuation { continuation in
                sut.remoteConfig { _, _ in continuation.resume() }
            }

            #expect(captured.request?.value(forHTTPHeaderField: "Authorization") == nil)
        }

        @Test("strips custom headers on a redirect to a different host")
        func stripsHeadersOnCrossHostRedirect() async throws {
            let captured = CapturedRequestBox()
            stub(condition: isHost("proxy.example.com")) { _ in
                HTTPStubsResponse(data: Data(), statusCode: 307, headers: ["Location": "https://other.example.com/flags"])
            }
            stub(condition: isHost("other.example.com")) { request in
                captured.set(request)
                return HTTPStubsResponse(jsonObject: ["featureFlags": [:]], statusCode: 200, headers: nil)
            }
            let config = PostHogConfig(projectToken: "test_project_token", host: "https://proxy.example.com")
            config.requestHeaders = ["Authorization": "Bearer test-jwt"]
            let sut = PostHogApi(config)

            await withCheckedContinuation { continuation in
                sut.flags(distinctId: "x", anonymousId: nil, groups: [:], personProperties: [:]) { _, _ in continuation.resume() }
            }

            #expect(captured.request?.value(forHTTPHeaderField: "Authorization") == nil)
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

        @Test("retries retryable HTTP status responses before returning flags", arguments: [502, 504])
        func retriesRetryableHTTPStatusResponses(statusCode: Int) async throws {
            server.reset(flagsCount: 2)

            var requestCount = 0
            let requestCountLock = NSLock()
            server.flagsResponseHandler = { _ in
                requestCountLock.lock()
                requestCount += 1
                let currentRequestCount = requestCount
                requestCountLock.unlock()

                if currentRequestCount == 1 {
                    return HTTPStubsResponse(jsonObject: ["error": "server error"], statusCode: Int32(statusCode), headers: nil)
                }

                return HTTPStubsResponse(
                    jsonObject: [
                        "errorsWhileComputingFlags": false,
                        "featureFlags": ["retry-flag": "success"],
                    ],
                    statusCode: 200,
                    headers: nil
                )
            }

            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost")
            config.featureFlagRequestMaxRetries = 1
            let sut = PostHogApi(config)

            let resp = await getApiResponse { completion in
                sut.flags(distinctId: "", anonymousId: "", groups: [:], personProperties: [:]) { data, error in
                    completion((data, error))
                }
            }

            let data = try #require(resp.0)
            #expect(data["errorsWhileComputingFlags"] as! Bool == false)
            #expect((data["featureFlags"] as? [String: Any])?["retry-flag"] as? String == "success")
            #expect(resp.1 == nil)
            #expect(server.flagsRequests.count == 2)
        }

        @Test("does not retry retryable HTTP status responses when feature flag request max retries is zero", arguments: [502, 504])
        func doesNotRetryRetryableHTTPStatusResponsesWhenFeatureFlagRequestMaxRetriesIsZero(statusCode: Int) async throws {
            server.reset(flagsCount: 1)
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: ["error": "server error"], statusCode: Int32(statusCode), headers: nil)
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

private final class CapturedRequestBox {
    private let lock = NSLock()
    private var stored: URLRequest?

    var request: URLRequest? {
        lock.withLock { stored }
    }

    func set(_ request: URLRequest) {
        lock.withLock { stored = request }
    }
}
