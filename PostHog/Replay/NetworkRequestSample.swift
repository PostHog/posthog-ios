//
//  NetworkRequestSample.swift
//  PostHog
//
//  Created by Yiannis Josephides on 11/11/2024.
//

#if os(iOS)
    import Foundation

    private let jsonRegex: String = "^application/.*json"
    private let xmlRegex: String = "^application/.*xml"

    class NetworkRequestSample: Identifiable {
        enum ContentType: String {
            case json
            case xml
            case html
            case image
            case other

            init(contentType: String) {
                switch contentType {
                case _ where contentType.matches(jsonRegex):
                    self = .json
                case _ where contentType.matches(xmlRegex) || contentType == "text/xml":
                    self = .xml
                case "text/html":
                    self = .html
                case _ where contentType.hasPrefix("image/"):
                    self = .image
                default:
                    self = .other
                }
            }
        }

        lazy var id = UUID().uuidString

        var timestamp = getCurrentTimeMilliseconds()
        var timeOrigin = getMonotonicTimeInMilliseconds()

        var requestStartTime: UInt64?
        var requestURL: URL?
        var requestMethod: String?
        var requestHeaders: [String: Any]?
        var requestContentType: ContentType?
        var requestContentTypeRaw: String?
        var requestBodyStr: String?
        var requestBodyLength: Int?

        var responseError: String?
        var responseData: NSMutableData?
        var responseStatus: Int?
        var responseContentType: ContentType?
        var responseContentTypeRaw: String?
        var responseStartTime: UInt64?
        var responseEndTime: UInt64?
        var responseHeaders: [String: Any]?
        var responseBodyStr: String?
        var responseBodyLength: Int?

        var durationMs: UInt64?

        var isProcessed: Bool = false

        // called when a request starts loading
        func start(request: URLRequest) {
            requestStartTime = getMonotonicTimeInMilliseconds()
            requestURL = request.url?.absoluteURL
            requestMethod = request.httpMethod
            requestHeaders = request.normalizedHeaderFields ?? [:]

            // grab content-type. Keys normalized with .lowercase()
            if let contentType = requestHeaders?["content-type"] as? String {
                let contentType = contentType.components(separatedBy: ";")[0]
                requestContentTypeRaw = contentType
                requestContentType = ContentType(contentType: contentType)
            }

            // grab request body
            if let requestData = request.httpBody ?? request.httpBodyStream?.consume() {
                if let responseContentType, responseContentType == .image {
                    // don't record response body for image types
                    let bodyStr = requestData.base64EncodedString(options: .endLineWithLineFeed)
                    requestBodyLength = bodyStr.count
                } else if let utfString = String(data: requestData, encoding: String.Encoding.utf8) {
                    requestBodyStr = utfString
                    requestBodyLength = utfString.count
                }
            }
        }

        // called on stopLoading (request was cancelled)
        func stop() {
            durationMs = relative(getMonotonicTimeInMilliseconds(), to: requestStartTime)
        }

        // called on didCompleteWithError
        func complete(response: URLResponse, error: Error?) {
            let completedTime = getMonotonicTimeInMilliseconds()
            responseEndTime = completedTime
            responseStatus = (response as? HTTPURLResponse)?.statusCode
            responseHeaders = response.normalizedHeaderFields ?? [:]
            responseError = error?.localizedDescription

            if let contentType = responseHeaders?["content-type"] as? String {
                let contentType = contentType.components(separatedBy: ";")[0]
                responseContentTypeRaw = contentType
                responseContentType = ContentType(contentType: contentType)
            }

            durationMs = relative(completedTime, to: requestStartTime)

            if let responseData = responseData as? Data {
                if let responseContentType, responseContentType == .image {
                    // don't record response body for image types
                    let bodyStr = responseData.base64EncodedString(options: .endLineWithLineFeed)
                    responseBodyLength = bodyStr.count
                } else if let utfString = String(data: responseData, encoding: String.Encoding.utf8) {
                    responseBodyStr = utfString
                    responseBodyLength = utfString.count
                }
            }
        }

        // called after startReceivingData when didReceiveData
        func didReceive(data: Data) {
            if responseStartTime == nil {
                responseStartTime = getMonotonicTimeInMilliseconds()
                responseData = NSMutableData()
            }
            responseData?.append(data)
        }

        // sample was queued upstream - for debug purposes
        func markProcessed() {
            isProcessed = true
        }
    }

    private func getMonotonicTimeInMilliseconds() -> UInt64 {
        // Get the raw mach time
        let machTime = mach_absolute_time()

        // Get timebase info to convert to nanoseconds
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)

        // Convert mach time to nanoseconds
        let nanoTime = machTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)

        // Convert nanoseconds to milliseconds
        let milliTime = nanoTime / NSEC_PER_MSEC

        return milliTime
    }

    private func getCurrentTimeMilliseconds() -> UInt64 {
        UInt64(now().timeIntervalSince1970) * MSEC_PER_SEC
    }

    extension NetworkRequestSample {
        func toDict() -> [String: Any] {
            [
                "entryType": "resource",
                "initiatorType": getInitiatorType(),
                "name": requestURL?.absoluteString,
                "method": requestMethod,

                "transferSize": responseData?.length,
                "timestamp": timestamp,
                "duration": durationMs,

                "requestStart": relative(toOrigin: requestStartTime),
                "requestBody": requestBodyStr,
                "requestHeaders": requestHeaders,

                "responseStart": relative(toOrigin: responseStartTime),
                "responseEnd": relative(toOrigin: responseEndTime),
                "responseStatus": responseStatus,
                "responseBody": responseBodyStr,
                "responseHeaders": responseHeaders,

                "startTime": 0, // always zero, needed for timeline views
                "endTime": relative(responseEndTime, to: requestStartTime),
            ].compactMapValues { $0 }
        }

        func getInitiatorType() -> String? {
            guard let type = requestContentType ?? responseContentType else {
                return "other"
            }
            return switch type {
            case .json, .html: "fetch"
            case .image: "img"
            case .xml: "xmlhttprequest"
            case .other: "other"
            }
        }

        func relative(toOrigin time: UInt64?) -> UInt64? {
            relative(time, to: timeOrigin)
        }

        func relative(_ date: UInt64?, to dateOrigin: UInt64?) -> UInt64? {
            guard let date, let dateOrigin, date >= dateOrigin else { return nil }
            return date - dateOrigin
        }
    }

    extension InputStream {
        func consume() -> Data {
            open()
            defer { close() }

            var data = Data()
            let bufferSize = 4096 // 4KB - typical buffer size
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            var bytesRead = 0

            repeat {
                bytesRead = read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    data.append(buffer, count: bytesRead)
                }
            } while bytesRead > 0

            return data
        }
    }

    extension String {
        func matches(_ regex: String) -> Bool {
            range(of: regex, options: .regularExpression, range: nil) != nil
        }
    }

    extension URLRequest {
        var normalizedHeaderFields: [String: Any]? {
            guard let headers = allHTTPHeaderFields else { return nil }
            return Dictionary(uniqueKeysWithValues: headers.map { key, value in
                (String(describing: key).lowercased(), "\(value)")
            })
        }
    }

    extension URLResponse {
        var normalizedHeaderFields: [String: Any]? {
            guard let headers = (self as? HTTPURLResponse)?.allHeaderFields else { return nil }
            return Dictionary(uniqueKeysWithValues: headers.map { key, value in
                (String(describing: key).lowercased(), "\(value)")
            })
        }
    }

#endif
