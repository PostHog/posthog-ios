#if os(iOS)
    import Foundation

    public extension URLSession {
        private func getMonotonicTimeInMilliseconds() -> UInt64 {
            // Get the raw mach time
            let machTime = mach_absolute_time()

            // Get timebase info to convert to nanoseconds
            var timebaseInfo = mach_timebase_info_data_t()
            mach_timebase_info(&timebaseInfo)

            // Convert mach time to nanoseconds
            let nanoTime = machTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)

            // Convert nanoseconds to milliseconds
            let milliTime = nanoTime / 1_000_000

            return milliTime
        }

        private func executeRequest(request: URLRequest? = nil,
                                    action: () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse)
        {
            let timestamp = Date()
            let startMillis = getMonotonicTimeInMilliseconds()
            var endMillis: UInt64?
            do {
                let (data, response) = try await action()
                endMillis = getMonotonicTimeInMilliseconds()
                captureData(request: request, response: response, timestamp: timestamp, start: startMillis, end: endMillis)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, timestamp: timestamp, start: startMillis, end: endMillis)
                throw error
            }
        }

        private func executeRequest(request: URLRequest? = nil,
                                    action: () async throws -> (URL, URLResponse)) async throws -> (URL, URLResponse)
        {
            let timestamp = Date()
            let startMillis = getMonotonicTimeInMilliseconds()
            var endMillis: UInt64?
            do {
                let (url, response) = try await action()
                endMillis = getMonotonicTimeInMilliseconds()
                captureData(request: request, response: response, timestamp: timestamp, start: startMillis, end: endMillis)
                return (url, response)
            } catch {
                captureData(request: request, response: nil, timestamp: timestamp, start: startMillis, end: endMillis)
                throw error
            }
        }

        func postHogData(for request: URLRequest) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await data(for: request) })
        }

        func postHogData(from url: URL) async throws -> (Data, URLResponse) {
            try await executeRequest(action: { try await data(from: url) })
        }

        func postHogUpload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, fromFile: fileURL) })
        }

        func postHogUpload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, from: bodyData) })
        }

        @available(iOS 15.0, *)
        func postHogData(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await data(for: request, delegate: delegate) })
        }

        @available(iOS 15.0, *)
        func postHogData(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(action: { try await data(from: url, delegate: delegate) })
        }

        @available(iOS 15.0, *)
        func postHogUpload(for request: URLRequest, fromFile fileURL: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, fromFile: fileURL, delegate: delegate) })
        }

        @available(iOS 15.0, *)
        func postHogUpload(for request: URLRequest, from bodyData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, from: bodyData, delegate: delegate) })
        }

        @available(iOS 15.0, *)
        func postHogDownload(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
            try await executeRequest(request: request, action: { try await download(for: request, delegate: delegate) })
        }

        @available(iOS 15.0, *)
        func postHogDownload(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
            try await executeRequest(action: { try await download(from: url, delegate: delegate) })
        }

        @available(iOS 15.0, *)
        func postHogDownload(resumeFrom resumeData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
            try await executeRequest(action: { try await download(resumeFrom: resumeData, delegate: delegate) })
        }

        // MARK: Private methods

        private func captureData(request: URLRequest? = nil, response: URLResponse? = nil, timestamp: Date, start: UInt64, end: UInt64? = nil) {
            // we dont check config.sessionReplayConfig.captureNetworkTelemetry here since this extension
            // has to be called manually anyway
            if !PostHogSDK.shared.isSessionReplayActive() {
                return
            }
            let currentEnd = end ?? getMonotonicTimeInMilliseconds()

            PostHogReplayIntegration.dispatchQueue.async {
                var snapshotsData: [Any] = []

                var requestsData: [String: Any] = ["duration": currentEnd - start,
                                                   "method": request?.httpMethod ?? "GET",
                                                   "name": request?.url?.absoluteString ?? (response?.url?.absoluteString ?? ""),
                                                   "initiatorType": "fetch",
                                                   "entryType": "resource",
                                                   "transferSize": response?.expectedContentLength ?? 0,
                                                   "timestamp": timestamp.toMillis()]

                if let urlResponse = response as? HTTPURLResponse {
                    requestsData["responseStatus"] = urlResponse.statusCode
                }

                let payloadData: [String: Any] = ["requests": [requestsData]]
                let pluginData: [String: Any] = ["plugin": "rrweb/network@1", "payload": payloadData]

                let recordingData: [String: Any] = ["type": 6, "data": pluginData, "timestamp": timestamp.toMillis()]
                snapshotsData.append(recordingData)

                PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData])
            }
        }
    }
#endif
