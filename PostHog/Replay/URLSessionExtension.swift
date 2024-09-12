#if os(iOS)
    public extension URLSession {
        func postHogData(for request: URLRequest) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await self.data(for: request)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        func postHogData(from url: URL) async throws -> (Data, URLResponse) {
            let before = Date()
            do {
                let (data, response) = try await self.data(from: url)
                let after = Date()
                captureData(request: nil, response: response, before: before, after: after)
                return (data, response)
            } catch {
                throw error
            }
        }

        func postHogUpload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await upload(for: request, fromFile: fileURL)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        func postHogUpload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await upload(for: request, from: bodyData)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogData(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await self.data(for: request, delegate: delegate)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogData(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await self.data(from: url, delegate: delegate)
                after = Date()
                captureData(request: nil, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: nil, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogUpload(for request: URLRequest, fromFile fileURL: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await upload(for: request, fromFile: fileURL, delegate: delegate)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogUpload(for request: URLRequest, from bodyData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (data, response) = try await upload(for: request, from: bodyData, delegate: delegate)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (data, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogDownload(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (fileURL, response) = try await download(for: request, delegate: delegate)
                after = Date()
                captureData(request: request, response: response, before: before, after: after)
                return (fileURL, response)
            } catch {
                captureData(request: request, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogDownload(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (fileURL, response) = try await download(from: url, delegate: delegate)
                after = Date()
                captureData(request: nil, response: response, before: before, after: after)
                return (fileURL, response)
            } catch {
                captureData(request: nil, response: nil, before: before, after: after)
                throw error
            }
        }

        @available(iOS 15.0, *)
        func postHogDownload(resumeFrom resumeData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
            let before = Date()
            var after: Date?
            do {
                let (fileURL, response) = try await download(resumeFrom: resumeData, delegate: delegate)
                after = Date()
                captureData(request: nil, response: response, before: before, after: after)
                return (fileURL, response)
            } catch {
                captureData(request: nil, response: nil, before: before, after: after)
                throw error
            }
        }

        // MARK: Private methods

        private func captureData(request: URLRequest? = nil, response: URLResponse? = nil, before: Date, after: Date? = nil) {
            // we dont check config.sessionReplayConfig.captureNetworkTelemetry here since this extension
            // has to be called manually anyway
            if !PostHogSDK.shared.isSessionReplayActive() {
                return
            }
            let currentAfter = after ?? Date()

            PostHogReplayIntegration.dispatchQueue.async {
                var snapshotsData: [Any] = []

                var requestsData: [String: Any] = ["duration": currentAfter.toMillis() - before.toMillis(),
                                                   "method": request?.httpMethod ?? "GET",
                                                   "name": request?.url?.absoluteString ?? (response?.url?.absoluteString ?? ""),
                                                   "initiatorType": "fetch",
                                                   "entryType": "resource",
                                                   "transferSize": response?.expectedContentLength ?? 0,
                                                   "timestamp": before.toMillis()]

                if let urlResponse = response as? HTTPURLResponse {
                    requestsData["responseStatus"] = urlResponse.statusCode
                }

                let payloadData: [String: Any] = ["requests": [requestsData]]
                let pluginData: [String: Any] = ["plugin": "rrweb/network@1", "payload": payloadData]

                let recordingData: [String: Any] = ["type": 6, "data": pluginData, "timestamp": currentAfter.toMillis()]
                snapshotsData.append(recordingData)

                PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData])
            }
        }
    }
#endif
