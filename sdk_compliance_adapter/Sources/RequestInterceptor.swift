import Foundation
import PostHog

#if os(Linux)
    import zlibLinux
#else
    import zlib
#endif

/// Tracks HTTP requests made by the PostHog SDK
struct TrackedRequest: Codable {
    let timestamp_ms: Int64
    let status_code: Int
    let retry_attempt: Int
    let event_count: Int
    let uuid_list: [String]
}

/// URLProtocol subclass that intercepts all HTTP requests
class RequestInterceptor: URLProtocol {
    static var trackedRequests: [TrackedRequest] = []
    static var totalEventsSent: Int = 0

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
                    // Server SDK format: {"api_key": "...", "batch": [...]}
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
            timestamp_ms: Int64(Date().timeIntervalSince1970 * 1000),
            status_code: response.statusCode,
            retry_attempt: retryCount,
            event_count: eventCount,
            uuid_list: uuidList
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
                    stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPointer.bindMemory(to: Bytef.self).baseAddress!).advanced(by: Int(inputStartPosition))
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
