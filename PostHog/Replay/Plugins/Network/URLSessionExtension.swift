#if os(iOS)
    import Foundation

    /// Convenience URLSession APIs that capture session replay network telemetry for manual requests.
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
            return nanoTime / 1_000_000
        }

        private func executeRequest<Result>(request: URLRequest? = nil,
                                            action: () async throws -> (Result, URLResponse),
                                            postHog: PostHogSDK?) async throws -> (Result, URLResponse)
        {
            let timestamp = Date()
            let startMillis = getMonotonicTimeInMilliseconds()
            var endMillis: UInt64?
            let sessionId = postHog?.sessionManager.getSessionId(at: timestamp)
            do {
                let (result, response) = try await action()
                endMillis = getMonotonicTimeInMilliseconds()
                captureData(request: request,
                            response: response,
                            sessionId: sessionId,
                            timestamp: timestamp,
                            start: startMillis,
                            end: endMillis,
                            postHog: postHog)
                return (result, response)
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

        /// Performs `data(for:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Request to execute.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.data(for:)`.
        func postHogData(for request: URLRequest, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await data(for: request) }, postHog: postHog)
        }

        /// Performs `data(from:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - url: URL to request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.data(from:)`.
        func postHogData(from url: URL, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse) {
            try await executeRequest(action: { try await data(from: url) }, postHog: postHog)
        }

        /// Performs `upload(for:fromFile:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Upload request to execute.
        ///   - fileURL: File URL to upload.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.upload(for:fromFile:)`.
        func postHogUpload(
            for request: URLRequest,
            fromFile fileURL: URL,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, fromFile: fileURL) }, postHog: postHog)
        }

        /// Performs `upload(for:from:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Upload request to execute.
        ///   - bodyData: Request body data to upload.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.upload(for:from:)`.
        func postHogUpload(
            for request: URLRequest,
            from bodyData: Data,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, from: bodyData) }, postHog: postHog)
        }

        /// Performs `data(for:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Request to execute.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.data(for:delegate:)`.
        @available(iOS 15.0, *)
        func postHogData(
            for request: URLRequest,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await data(for: request, delegate: delegate) }, postHog: postHog)
        }

        /// Performs `data(from:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - url: URL to request.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.data(from:delegate:)`.
        @available(iOS 15.0, *)
        func postHogData(
            from url: URL,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(action: { try await data(from: url, delegate: delegate) }, postHog: postHog)
        }

        /// Performs `upload(for:fromFile:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Upload request to execute.
        ///   - fileURL: File URL to upload.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.upload(for:fromFile:delegate:)`.
        @available(iOS 15.0, *)
        func postHogUpload(
            for request: URLRequest,
            fromFile fileURL: URL,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, fromFile: fileURL, delegate: delegate) }, postHog: postHog)
        }

        /// Performs `upload(for:from:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Upload request to execute.
        ///   - bodyData: Request body data to upload.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The data and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.upload(for:from:delegate:)`.
        @available(iOS 15.0, *)
        func postHogUpload(
            for request: URLRequest,
            from bodyData: Data,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (Data, URLResponse) {
            try await executeRequest(request: request, action: { try await upload(for: request, from: bodyData, delegate: delegate) }, postHog: postHog)
        }

        /// Performs `download(for:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - request: Download request to execute.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The downloaded file URL and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.download(for:delegate:)`.
        @available(iOS 15.0, *)
        func postHogDownload(
            for request: URLRequest,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (URL, URLResponse) {
            try await executeRequest(request: request, action: { try await download(for: request, delegate: delegate) }, postHog: postHog)
        }

        /// Performs `download(from:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - url: URL to download.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The downloaded file URL and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.download(from:delegate:)`.
        @available(iOS 15.0, *)
        func postHogDownload(
            from url: URL,
            delegate: (any URLSessionTaskDelegate)? = nil,
            postHog: PostHogSDK? = nil
        ) async throws -> (URL, URLResponse) {
            try await executeRequest(action: { try await download(from: url, delegate: delegate) }, postHog: postHog)
        }

        /// Performs `download(resumeFrom:delegate:)` and captures network telemetry for session replay.
        ///
        /// - Parameters:
        ///   - resumeData: Resume data from a previously cancelled download.
        ///   - delegate: Task delegate for the request.
        ///   - postHog: SDK instance used to read the session ID and emit telemetry.
        ///     Pass an initialized instance; `nil` performs the request without capturing replay telemetry.
        /// - Returns: The downloaded file URL and URL response returned by `URLSession`.
        /// - Throws: Any error thrown by `URLSession.download(resumeFrom:delegate:)`.
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
