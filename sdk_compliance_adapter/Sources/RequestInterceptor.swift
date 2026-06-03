import Foundation
import PostHog

#if os(Linux)
    import zlibLinux
#else
    import zlib
#endif

/// Tracks HTTP requests made by the PostHog SDK
struct TrackedRequest: Codable {
    let timestampMs: Int64
    let statusCode: Int
    let retryAttempt: Int
    let eventCount: Int
    let uuidList: [String]

    enum CodingKeys: String, CodingKey {
        case timestampMs = "timestamp_ms"
        case statusCode = "status_code"
        case retryAttempt = "retry_attempt"
        case eventCount = "event_count"
        case uuidList = "uuid_list"
    }
}

/// URLProtocol subclass that intercepts all HTTP requests
class RequestInterceptor: URLProtocol {
    static var trackedRequests: [TrackedRequest] = []
    static var totalEventsSent: Int = 0

    private static let condition = NSCondition()
    private static var _inFlightCount = 0

    static var inFlightCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return _inFlightCount
    }

    private static func incrementInFlight() {
        condition.lock()
        _inFlightCount += 1
        condition.broadcast()
        condition.unlock()
    }

    private static func decrementInFlight() {
        condition.lock()
        _inFlightCount = max(0, _inFlightCount - 1)
        condition.broadcast()
        condition.unlock()
    }

    /// Returns once the in-flight count has been 0 for `stabilityWindow` after seeing at least
    /// one request, or after `gracePeriod` if nothing flew. Times out after `timeout`.
    static func waitForFlushSettle(
        timeout: TimeInterval = 30.0,
        gracePeriod: TimeInterval = 0.1,
        stabilityWindow: TimeInterval = 2.5
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let absoluteDeadline = Date().addingTimeInterval(timeout)
                var sawRequest = false
                var idleSince: Date?

                condition.lock()
                defer { condition.unlock() }

                while Date() < absoluteDeadline {
                    if _inFlightCount > 0 {
                        sawRequest = true
                        idleSince = nil
                    } else if idleSince == nil {
                        idleSince = Date()
                    }

                    let wakeBy: Date = {
                        guard let since = idleSince else { return absoluteDeadline }
                        let window = sawRequest ? stabilityWindow : gracePeriod
                        return min(since.addingTimeInterval(window), absoluteDeadline)
                    }()

                    if Date() >= wakeBy {
                        if _inFlightCount == 0 {
                            continuation.resume()
                            return
                        }
                        continue
                    }

                    condition.wait(until: wakeBy)
                }
                print("[INTERCEPTOR] waitForFlushSettle timed out after \(timeout)s with \(_inFlightCount) in flight")
                continuation.resume()
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Only intercept requests to the mock server (not to real PostHog endpoints)
        guard let url = request.url else { return false }

        // Intercept /batch and /e/ endpoints, but not /flags/ or /config
        let urlString = url.absoluteString
        if urlString.contains("/batch") || urlString.contains("/e/") || urlString.contains("/s/"),
           !urlString.contains("/flags"),
           !urlString.contains("/config")
        {
            print("[INTERCEPTOR] Can handle: \(urlString)")
            return true
        }

        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = self.request
        print("[INTERCEPTOR] startLoading called for: \(request.url?.absoluteString ?? "nil")")

        // Capture the request body BEFORE sending (for upload tasks, httpBody contains the gzipped data)
        let requestBody = request.httpBody

        // Create a URLSession to actually perform the request
        // IMPORTANT: Use .default to avoid recursion (our custom config is only for PostHog SDK)
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            Self.decrementInFlight()
            print("[INTERCEPTOR] Task completed for: \(request.url?.absoluteString ?? "nil"), error: \(error?.localizedDescription ?? "none")")
            guard let self = self else { return }

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }

            // Track the request (pass the captured body)
            self.trackRequest(request: request, response: httpResponse, requestBody: requestBody)

            // Forward the response to the client
            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        Self.incrementInFlight()
        task.resume()
    }

    override func stopLoading() {
        // Nothing to do
    }

    private func trackRequest(request: URLRequest, response: HTTPURLResponse, requestBody: Data?) {
        guard let url = request.url else { return }

        print("[INTERCEPTOR] Tracking request to: \(url.absoluteString)")
        print("[INTERCEPTOR] Status code: \(response.statusCode)")

        var events: [[String: Any]] = []
        var eventCount = 0
        var uuidList: [String] = []

        // Parse the request body to extract events
        print("[INTERCEPTOR] requestBody is nil: \(requestBody == nil), size: \(requestBody?.count ?? 0)")
        if let bodyData = requestBody {
            print("[INTERCEPTOR] Parsing body data, size: \(bodyData.count)")
            do {
                // Try to decompress if it's gzipped using the PostHog SDK's gunzipped() method
                let decompressed: Data
                if let contentEncoding = request.allHTTPHeaderFields?["Content-Encoding"],
                   contentEncoding.contains("gzip")
                {
                    // Use the same gunzipped() method that PostHog SDK uses
                    decompressed = try bodyData.gunzipped()
                    print("[INTERCEPTOR] Decompressed gzipped payload")
                } else {
                    decompressed = bodyData
                }

                if let json = try JSONSerialization.jsonObject(with: decompressed) as? [String: Any] {
                    // Server SDK format: {"api_key": "...", "batch": [...]} where api_key carries the project token.
                    if let batch = json["batch"] as? [[String: Any]] {
                        events = batch
                        print("[INTERCEPTOR] Found batch with \(events.count) events")
                    }
                } else if let jsonArray = try? JSONSerialization.jsonObject(with: decompressed) as? [[String: Any]] {
                    // Client SDK format: [{event}, {event}, ...]
                    events = jsonArray
                    print("[INTERCEPTOR] Found array with \(events.count) events")
                }

                eventCount = events.count
                uuidList = events.compactMap { $0["uuid"] as? String }

                print("[INTERCEPTOR] Extracted \(eventCount) events with UUIDs: \(uuidList)")
            } catch {
                print("[INTERCEPTOR] Error parsing request body: \(error)")
            }
        }

        // Extract retry count from URL
        let retryCount: Int
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let retryParam = components.queryItems?.first(where: { $0.name == "retry_count" }),
           let retryValue = retryParam.value,
           let retry = Int(retryValue)
        {
            retryCount = retry
        } else {
            retryCount = 0
        }

        let trackedRequest = TrackedRequest(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            statusCode: response.statusCode,
            retryAttempt: retryCount,
            eventCount: eventCount,
            uuidList: uuidList
        )

        RequestInterceptor.trackedRequests.append(trackedRequest)

        if response.statusCode == 200 {
            RequestInterceptor.totalEventsSent += eventCount
            print("[INTERCEPTOR] Successfully sent \(eventCount) events (total: \(RequestInterceptor.totalEventsSent))")
        }
    }

    static func reset() {
        trackedRequests = []
        totalEventsSent = 0
        condition.lock()
        _inFlightCount = 0
        condition.broadcast()
        condition.unlock()
        print("[INTERCEPTOR] Reset state")
    }
}

// MARK: - Gzip Decompression Extension

// Based on https://github.com/1024jp/GzipSwift (MIT License)
// Also used in PostHog SDK at PostHog/Utils/Data+Gzip.swift

private enum GzipConstants {
    static let maxWindowBits = MAX_WBITS
    static let chunk = 1 << 14
    static let streamSize = MemoryLayout<z_stream>.size
}

extension Data {
    /// Decompress gzip data
    func gunzipped() throws -> Data {
        guard !isEmpty else {
            return Data()
        }

        var data = Data(capacity: count * 2)
        var totalIn: uLong = 0
        var totalOut: uLong = 0

        repeat {
            var stream = z_stream()
            var status: Int32

            let wBits = GzipConstants.maxWindowBits + 32
            status = inflateInit2_(&stream, wBits, ZLIB_VERSION, Int32(GzipConstants.streamSize))

            guard status == Z_OK else {
                throw NSError(domain: "gunzip", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "inflateInit2 failed"])
            }

            repeat {
                if Int(totalOut + stream.total_out) >= data.count {
                    data.count += count / 2
                }

                let inputCount = count
                let outputCount = data.count

                withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) in
                    let inputStartPosition = totalIn + stream.total_in
                    let baseAddress = inputPointer.bindMemory(to: Bytef.self).baseAddress!
                    stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
                        .advanced(by: Int(inputStartPosition))
                    stream.avail_in = uInt(inputCount) - uInt(inputStartPosition)

                    data.withUnsafeMutableBytes { (outputPointer: UnsafeMutableRawBufferPointer) in
                        let outputStartPosition = totalOut + stream.total_out
                        stream.next_out = outputPointer.bindMemory(to: Bytef.self).baseAddress!.advanced(by: Int(outputStartPosition))
                        stream.avail_out = uInt(outputCount) - uInt(outputStartPosition)

                        status = inflate(&stream, Z_SYNC_FLUSH)

                        stream.next_out = nil
                    }

                    stream.next_in = nil
                }
            } while status == Z_OK

            totalIn += stream.total_in

            guard inflateEnd(&stream) == Z_OK, status == Z_STREAM_END else {
                throw NSError(domain: "gunzip", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "inflate failed"])
            }

            totalOut += stream.total_out

        } while totalIn < count

        data.count = Int(totalOut)

        return data
    }
}
