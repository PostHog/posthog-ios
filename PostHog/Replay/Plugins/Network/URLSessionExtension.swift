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
                                    action: () async throws -> (Data, URLResponse),
                                    postHog: PostHogSDK?) async throws -> (Data, URLResponse)
        {
            let timestamp = Date()
            let startMillis = getMonotonicTimeInMilliseconds()
            var endMillis: UInt64?
            let sessionId = PostHogSessionManager.shared.getSessionId(at: timestamp)
            do {
                let (data, response) = try await action()
                endMillis = getMonotonicTimeInMilliseconds()
                captureData(request: request,
                            response: response,
                            sessionId: sessionId,
                            timestamp: timestamp,
                            start: startMillis,
                            end: endMillis,
                            postHog: postHog)
                return (data, response)
            } catch {
                captureData(request: request,
                            response: nil,
                            sessionId: sessionId,
                            timestamp: timestamp,
                            start: startMillis,
                            end: endMillis,
                            postHog: postHog)
                throw error
            }
        }

        private func executeRequest(request: URLRequest? = nil,
                                    action: () async throws -> (URL, URLResponse),
                                    postHog: PostHogSDK?) async throws -> (URL, URLResponse)
        {
            let timestamp = Date()
            let startMillis = getMonotonicTimeInMilliseconds()
            var endMillis: UInt64?
            let sessionId = PostHogSessionManager.shared.getSessionId(at: timestamp)
            do {
                let (url, response) = try await action()
                endMillis = getMonotonicTimeInMilliseconds()
                captureData(request: request,
                            response: response,
                            sessionId: sessionId,
                            timestamp: timestamp,
                            start: startMillis,
                            end: endMillis,
                            postHog: postHog)
                return (url, response)
            } catch {
                captureData(request: request,
                            response: nil,
                            sessionId: sessionId,
                            timestamp: timestamp,
                            start: startMillis,
                            end: endMillis,
                            postHog: postHog)
                throw error
            }
        }

        func postHogData(for request: URLRequest, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await data(for: request) }, postHog: postHog)
        }

        func postHogData(from url: URL, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(action: { try await data(from: url) }, postHog: postHog)
        }

        func postHogUpload(
            for request: URLRequest,
            fromFile fileURL: URL,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, fromFile: fileURL) }, postHog: postHog)
        }

        func postHogUpload(
            for request: URLRequest,
            from bodyData: Data,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, from: bodyData) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogData(
            for request: URLRequest,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await data(for: request, delegate: delegate) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogData(
            from url: URL,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(action: { try await data(from: url, delegate: delegate) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogUpload(
            for request: URLRequest,
            fromFile fileURL: URL,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, fromFile: fileURL, delegate: delegate) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogUpload(
            for request: URLRequest,
            from bodyData: Data,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, from: bodyData, delegate: delegate) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogDownload(
            for request: URLRequest,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (URL, URLResponse) {
            try await executeRequest(request: request, action: { try await download(for: request, delegate: delegate) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogDownload(
            from url: URL,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (URL, URLResponse) {
            try await executeRequest(action: { try await download(from: url, delegate: delegate) }, postHog: postHog)
        }

        @available(iOS 15.0, *)
        func postHogDownload(
            resumeFrom resumeData: Data,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (URL, URLResponse) {
            try await executeRequest(action: { try await download(resumeFrom: resumeData, delegate: delegate) }, postHog: postHog)
        }

        // MARK: Private methods

        private func captureData(
            request: URLRequest? = nil,
            response: URLResponse? = nil,
            sessionId: String?,
            timestamp: Date,
            start: UInt64,
            end: UInt64? = nil,
            postHog: PostHogSDK?
        ) {
            let instance = postHog ?? PostHogSDK.shared

            // we don't check config.sessionReplayConfig.captureNetworkTelemetry here since this extension
            // has to be called manually anyway
            guard let sessionId, instance.isSessionReplayActive() else {
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
                                                   "timestamp": timestamp.toMillis()]

                // the UI special case if the transferSize is 0 as coming from cache
                let transferSize = Int64(request?.httpBody?.count ?? 0) + (response?.expectedContentLength ?? 0)
                if transferSize > 0 {
                    requestsData["transferSize"] = transferSize
                }

                if let urlResponse = response as? HTTPURLResponse {
                    requestsData["responseStatus"] = urlResponse.statusCode
                }

                let payloadData: [String: Any] = ["requests": [requestsData]]
                let pluginData: [String: Any] = ["plugin": "rrweb/network@1", "payload": payloadData]

                let recordingData: [String: Any] = ["type": 6, "data": pluginData, "timestamp": timestamp.toMillis()]
                snapshotsData.append(recordingData)

                instance.capture(
                    "$snapshot",
                    properties: [
                        "$snapshot_source": "mobile",
                        "$snapshot_data": snapshotsData,
                        "$session_id": sessionId,
                    ],
                    timestamp: timestamp
                )
            }
        }
    }
#endif
