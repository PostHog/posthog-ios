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
    private static let trackerLock = NSLock()
    private static var currentTracker = RequestTracker()
    static var tracker: RequestTracker {
        get {
            trackerLock.lock()
            defer { trackerLock.unlock() }
            return currentTracker
        }
        set {
            trackerLock.lock()
            defer { trackerLock.unlock() }
            currentTracker = newValue
        }
    }

    private static let proxySession = URLSession(configuration: .default)
    private var proxyTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        // Flags use the SDK's session directly. Only analytics uploads need passive
        // UUID/acknowledgment observation for the adapter's flush and state endpoints.
        request.url?.path == "/batch"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = self.request
        print("[INTERCEPTOR] startLoading called for: \(request.url?.absoluteString ?? "nil")")

        // Capture the request body BEFORE sending. Upload tasks may provide the body
        // as a stream rather than httpBody, so normalize it onto the proxied request.
        let requestBody = Self.extractBody(from: request)
        var proxiedRequest = request
        if proxiedRequest.httpBody == nil, let requestBody {
            proxiedRequest.httpBody = requestBody
        }

        // Actually perform the request. Keep the proxy session alive for the process;
        // a local URLSession can be deallocated while the task is still running, which
        // leaves /flush waiting forever for in-flight interception to settle.
        let tracker = Self.tracker
        let startedAt = Int64(Date().timeIntervalSince1970 * 1000)
        proxyTask = Self.proxySession.dataTask(with: proxiedRequest) { [weak self] data, response, error in
            defer { tracker.endRequest() }
            print("[INTERCEPTOR] Task completed for: \(proxiedRequest.url?.absoluteString ?? "nil"), error: \(error?.localizedDescription ?? "none")")
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
            self.trackRequest(request: proxiedRequest, response: httpResponse, requestBody: requestBody,
                              tracker: tracker, startedAt: startedAt)

            // Forward the response to the client in URLProtocol's expected order.
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        tracker.beginRequest()
        proxyTask?.resume()
    }

    override func stopLoading() {
        proxyTask?.cancel()
    }

    private static func extractBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 16 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }

        return data.isEmpty ? nil : data
    }

    private func trackRequest(request: URLRequest, response: HTTPURLResponse, requestBody: Data?,
                              tracker: RequestTracker, startedAt: Int64)
    {
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

        tracker.observeResponse(status: response.statusCode, uuids: uuidList, timestampMs: startedAt)
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
