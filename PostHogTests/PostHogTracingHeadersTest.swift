#if os(iOS)
    import Foundation
    import OHHTTPStubs
    import OHHTTPStubsSwift
    @testable import PostHog
    import Testing

    struct ClassicTracingCase: CustomTestStringConvertible, Sendable {
        enum Invocation: Sendable {
            case dataTaskWithRequest
            case dataTaskWithURL
            case dataTaskWithCustomSession
            case uploadTaskWithRequest
            case downloadTaskWithRequest
        }

        let name: String
        let invocation: Invocation

        var testDescription: String { name }
    }

    struct AsyncTracingCase: CustomTestStringConvertible, Sendable {
        enum Invocation: Sendable {
            case dataForRequest
            case dataFromURL
            case uploadForRequest
            case uploadFileForRequest
            case downloadForRequest
            case downloadFromURL
            case bytesForRequest
            case bytesFromURL
        }

        let name: String
        let invocation: Invocation

        var testDescription: String { name }
    }

    @Suite("Tracing headers", .serialized)
    struct PostHogTracingHeadersTest {
        private static let primaryHost = "api.example.com"
        private static let otherHost = "other.example.com"
        private static let subdomainHost = "sub.api.example.com"

        private static let distinctIdHeader = "X-POSTHOG-DISTINCT-ID"
        private static let sessionIdHeader = "X-POSTHOG-SESSION-ID"
        private static let windowIdHeader = "X-POSTHOG-WINDOW-ID"

        private static let payloadData = Data("payload".utf8)

        private static let classicCases: [ClassicTracingCase] = [
            .init(name: "dataTask(with: URLRequest, completionHandler:)", invocation: .dataTaskWithRequest),
            .init(name: "dataTask(with: URL, completionHandler:)", invocation: .dataTaskWithURL),
            .init(name: "dataTask(with: URLRequest, completionHandler:) on custom URLSession", invocation: .dataTaskWithCustomSession),
            .init(name: "uploadTask(with:from:completionHandler:)", invocation: .uploadTaskWithRequest),
            .init(name: "downloadTask(with:completionHandler:)", invocation: .downloadTaskWithRequest),
        ]

        private static let asyncCases: [AsyncTracingCase] = [
            .init(name: "data(for:)", invocation: .dataForRequest),
            .init(name: "data(from:)", invocation: .dataFromURL),
            .init(name: "upload(for:from:)", invocation: .uploadForRequest),
            .init(name: "upload(for:fromFile:)", invocation: .uploadFileForRequest),
            .init(name: "download(for:)", invocation: .downloadForRequest),
            .init(name: "download(from:)", invocation: .downloadFromURL),
            .init(name: "bytes(for:)", invocation: .bytesForRequest),
            .init(name: "bytes(from:)", invocation: .bytesFromURL),
        ]

        @Test("adds distinct and session tracing headers to listed hosts for classic URLSession APIs", arguments: classicCases)
        func addsHeadersToListedHostsForClassicURLSessionAPIs(_ testCase: ClassicTracingCase) async throws {
            try await withTracingSut(addTracingHeaders: [Self.primaryHost]) { sut in
                let capture = CapturedRequest()
                stubRequest(host: Self.primaryHost, capture: capture)

                try await invokeClassicTracingCase(testCase)

                let capturedRequest = try #require(capture.request)
                let sessionId = try #require(sut.getSessionId())
                assertTracingHeaders(capturedRequest, sut: sut, expectedSessionId: sessionId)
            }
        }

        @Test("normalizes configured hostnames while keeping exact host matching")
        func normalizesConfiguredHostnamesWhileKeepingExactHostMatching() async throws {
            try await withTracingSut(addTracingHeaders: ["  API.EXAMPLE.COM  "]) { sut in
                let matchingCapture = CapturedRequest()
                stubRequest(host: Self.primaryHost, capture: matchingCapture)

                try await performDataTask(with: try makeURL(host: Self.primaryHost))

                let matchingRequest = try #require(matchingCapture.request)
                #expect(matchingRequest.value(forHTTPHeaderField: Self.distinctIdHeader) == sut.getDistinctId())

                HTTPStubs.removeAllStubs()

                let nonMatchingCapture = CapturedRequest()
                stubRequest(host: Self.subdomainHost, capture: nonMatchingCapture)

                try await performDataTask(with: try makeURL(host: Self.subdomainHost))

                let nonMatchingRequest = try #require(nonMatchingCapture.request)
                assertNoTracingHeaders(nonMatchingRequest)
            }
        }

        @Test("adds distinct and session tracing headers to listed hosts for async await URLSession APIs", arguments: asyncCases)
        func addsHeadersToListedHostsForAsyncAwaitURLSessionAPIs(_ testCase: AsyncTracingCase) async throws {
            guard #available(iOS 15.0, *) else {
                return
            }

            try await withTracingSut(addTracingHeaders: [Self.primaryHost]) { sut in
                let capture = CapturedRequest()
                stubRequest(host: Self.primaryHost, capture: capture)

                try await invokeAsyncTracingCase(testCase)

                let capturedRequest = try #require(capture.request)
                let sessionId = try #require(sut.getSessionId())
                assertTracingHeaders(capturedRequest, sut: sut, expectedSessionId: sessionId)
            }
        }

        @Test("applies request modifiers only once for URL overloads")
        func appliesRequestModifiersOnlyOnceForURLOverloads() async throws {
            HTTPStubs.removeAllStubs()

            let modifierInvocationCount = Counter()
            let registrationId = try URLSessionInstrumentation.shared.register(requestModifier: { request in
                let invocationCount = modifierInvocationCount.incrementAndGet()
                var request = request
                request.setValue(String(invocationCount), forHTTPHeaderField: "X-POSTHOG-MODIFIER-COUNT")
                return request
            })
            defer {
                URLSessionInstrumentation.shared.unregister(registrationId)
                HTTPStubs.removeAllStubs()
            }

            let capture = CapturedRequest()
            stubRequest(host: Self.primaryHost, capture: capture)

            try await performDataTask(with: makeURL(host: Self.primaryHost))

            let capturedRequest = try #require(capture.request)

            #expect(modifierInvocationCount.value == 1)
            #expect(capturedRequest.value(forHTTPHeaderField: "X-POSTHOG-MODIFIER-COUNT") == "1")
        }

        @Test("does not add tracing headers to unlisted hosts for URL data tasks")
        func doesNotAddHeadersToUnlistedHostsForURLDataTasks() async throws {
            try await withTracingSut(addTracingHeaders: [Self.primaryHost]) { _ in
                let capture = CapturedRequest()
                stubRequest(host: Self.otherHost, capture: capture)

                try await performDataTask(with: try makeURL(host: Self.otherHost))

                let capturedRequest = try #require(capture.request)
                assertNoTracingHeaders(capturedRequest)
            }
        }

        @Test("keeps distinct id header but omits session tracing headers when the session has ended")
        func omitsSessionHeadersWhenSessionHasEnded() async throws {
            try await withTracingSut(addTracingHeaders: [Self.primaryHost]) { sut in
                sut.endSession()

                let capture = CapturedRequest()
                stubRequest(host: Self.primaryHost, capture: capture)

                try await performDataTask(with: try makeURL(host: Self.primaryHost))

                let capturedRequest = try #require(capture.request)
                assertTracingHeaders(capturedRequest, sut: sut, expectedSessionId: nil)
            }
        }

        private func withTracingSut<T>(
            addTracingHeaders: [String],
            _ body: (PostHogSDK) async throws -> T
        ) async throws -> T {
            PostHogTracingHeadersIntegration.clearInstalls()
            HTTPStubs.removeAllStubs()

            let sut = makeSut(addTracingHeaders: addTracingHeaders)
            defer {
                sut.close()
                HTTPStubs.removeAllStubs()
                PostHogTracingHeadersIntegration.clearInstalls()
            }

            return try await body(sut)
        }

        private func invokeClassicTracingCase(_ testCase: ClassicTracingCase) async throws {
            let url = try makeURL(host: Self.primaryHost)
            let request = URLRequest(url: url)

            switch testCase.invocation {
            case .dataTaskWithRequest:
                try await performDataTask(with: request)
            case .dataTaskWithURL:
                try await performDataTask(with: url)
            case .dataTaskWithCustomSession:
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                try await performDataTask(with: request, using: session)
            case .uploadTaskWithRequest:
                try await performUploadTask(with: request, body: Self.payloadData)
            case .downloadTaskWithRequest:
                try await performDownloadTask(with: request)
            }
        }

        @available(iOS 15.0, *)
        private func invokeAsyncTracingCase(_ testCase: AsyncTracingCase) async throws {
            let url = try makeURL(host: Self.primaryHost)
            let request = URLRequest(url: url)

            switch testCase.invocation {
            case .dataForRequest:
                _ = try await URLSession.shared.data(for: request)
            case .dataFromURL:
                _ = try await URLSession.shared.data(from: url)
            case .uploadForRequest:
                _ = try await URLSession.shared.upload(for: request, from: Self.payloadData)
            case .uploadFileForRequest:
                try await withTemporaryFile(contents: Self.payloadData) { fileURL in
                    _ = try await URLSession.shared.upload(for: request, fromFile: fileURL)
                }
            case .downloadForRequest:
                _ = try await URLSession.shared.download(for: request)
            case .downloadFromURL:
                _ = try await URLSession.shared.download(from: url)
            case .bytesForRequest:
                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                try await consumeFirstByte(from: bytes)
            case .bytesFromURL:
                let (bytes, _) = try await URLSession.shared.bytes(from: url)
                try await consumeFirstByte(from: bytes)
            }
        }

        @available(iOS 15.0, *)
        private func consumeFirstByte(from bytes: URLSession.AsyncBytes) async throws {
            var iterator = bytes.makeAsyncIterator()
            _ = try await iterator.next()
        }

        private func assertTracingHeaders(_ request: URLRequest, sut: PostHogSDK, expectedSessionId: String?) {
            #expect(request.value(forHTTPHeaderField: Self.distinctIdHeader) == sut.getDistinctId())
            #expect(request.value(forHTTPHeaderField: Self.sessionIdHeader) == expectedSessionId)
            #expect(request.value(forHTTPHeaderField: Self.windowIdHeader) == nil)
        }

        private func assertNoTracingHeaders(_ request: URLRequest) {
            #expect(request.value(forHTTPHeaderField: Self.distinctIdHeader) == nil)
            #expect(request.value(forHTTPHeaderField: Self.sessionIdHeader) == nil)
            #expect(request.value(forHTTPHeaderField: Self.windowIdHeader) == nil)
        }

        private func makeURL(host: String) throws -> URL {
            try #require(URL(string: "https://\(host)/test"))
        }

        private func makeSut(addTracingHeaders: [String]) -> PostHogSDK {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.addTracingHeaders = addTracingHeaders
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableRemoteConfigForTesting = true

            let storage = PostHogStorage(config)
            storage.reset()

            return PostHogSDK.with(config)
        }

        private func stubRequest(host: String, capture: CapturedRequest) {
            stub(condition: isHost(host)) { request in
                capture.set(request)
                return HTTPStubsResponse(
                    data: Data("ok".utf8),
                    statusCode: 200,
                    headers: ["Content-Type": "text/plain"]
                )
            }
        }

        private func performDataTask(with request: URLRequest, using session: URLSession = .shared) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.dataTask(with: request) { _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
                task.resume()
            }
        }

        private func performDataTask(with url: URL, using session: URLSession = .shared) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.dataTask(with: url) { _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
                task.resume()
            }
        }

        private func performUploadTask(with request: URLRequest, body: Data, using session: URLSession = .shared) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.uploadTask(with: request, from: body) { _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
                task.resume()
            }
        }

        private func performDownloadTask(with request: URLRequest, using session: URLSession = .shared) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: request) { _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
                task.resume()
            }
        }

        private func withTemporaryFile<T>(
            contents: Data,
            _ body: (URL) async throws -> T
        ) async throws -> T {
            let fileURL = try makeTemporaryFile(contents: contents)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            return try await body(fileURL)
        }

        private func makeTemporaryFile(contents: Data) throws -> URL {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("bin")
            try contents.write(to: fileURL)
            return fileURL
        }
    }

    private final class CapturedRequest {
        private let lock = NSLock()
        private var _request: URLRequest?

        var request: URLRequest? {
            lock.withLock { _request }
        }

        func set(_ request: URLRequest) {
            lock.withLock {
                _request = request
            }
        }
    }

    private final class Counter {
        private let lock = NSLock()
        private var _value = 0

        var value: Int {
            lock.withLock { _value }
        }

        func incrementAndGet() -> Int {
            lock.withLock {
                _value += 1
                return _value
            }
        }
    }
#endif
