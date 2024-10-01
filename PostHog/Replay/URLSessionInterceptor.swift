/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

    import Foundation

    class URLSessionInterceptor {
        private let config: PostHogConfig

        private let tasksLock = NSLock()

        init(_ config: PostHogConfig) {
            self.config = config
        }

        /// An internal queue for synchronising the access to `samplesByTask`.
        private let queue = DispatchQueue(label: "com.posthog.URLSessionInterceptor", target: .global(qos: .utility))
        private var samplesByTask: [URLSessionTask: NetworkSample] = [:]

        // MARK: - Interception Flow

        /// Notifies the `URLSessionTask` creation.
        /// This method should be called as soon as the task was created.
        /// - Parameter task: the task object obtained from `URLSession`.
        func taskCreated(task: URLSessionTask, session _: URLSession? = nil) {
            if !isCaptureNetworkEnabled() {
                return
            }
            guard let request = task.originalRequest else {
                return
            }

            guard let url = request.url else {
                return
            }

            let date = Date()
            queue.async {
                let sample = NetworkSample(timeOrigin: date, url: url.absoluteString)

                self.tasksLock.withLock {
                    self.samplesByTask[task] = sample
                }
            }
        }

        /// Notifies the `URLSessionTask` data receiving.
        /// This method should be called as soon as the next chunk of data is received by `URLSessionDataDelegate`.
        /// - Parameters:
        ///   - task: task receiving data.
        ///   - data: next chunk of data delivered to `URLSessionDataDelegate`.
        func taskReceivedData(task _: URLSessionTask, data _: Data) {
            // Currently we don't do anything with this
        }

        /// Notifies the `URLSessionTask` completion.
        /// This method should be called as soon as the task was completed.
        /// - Parameter task: the task object obtained from `URLSession`.
        /// - Parameter error: optional `Error` if the task completed with error.
        func taskCompleted(task: URLSessionTask, error _: Error?) {
            if !isCaptureNetworkEnabled() {
                return
            }

            guard let request = task.originalRequest else {
                return
            }
            let date = Date()

            queue.async {
                var sampleTask: NetworkSample?
                self.tasksLock.withLock {
                    sampleTask = self.samplesByTask[task]
                }
                let sampleTask = self.samplesByTask[task]
                guard var sample = sampleTask else {
                    return
                }

                let responseStatusCode = self.urlResponseStatusCode(response: task.response)

                if responseStatusCode != -1 {
                    sample.responseStatus = responseStatusCode
                }

                sample.httpMethod = request.httpMethod
                sample.initiatorType = "fetch"
                sample.duration = (date.toMillis() - sample.timeOrigin.toMillis())

                // the UI special case if the transferSize is 0 as coming from cache
                let transferSize = Int64(request.httpBody?.count ?? 0) + (task.response?.expectedContentLength ?? 0)
                if transferSize > 0 {
                    sample.decodedBodySize = transferSize
                }

                self.finish(task: task, sample: sample)
            }
        }

        // MARK: - Private

        private func urlResponseStatusCode(response: URLResponse?) -> Int {
            if let urlResponse = response as? HTTPURLResponse {
                return urlResponse.statusCode
            }
            return -1
        }

        private func isCaptureNetworkEnabled() -> Bool {
            config.sessionReplayConfig.captureNetworkTelemetry && PostHogSDK.shared.isSessionReplayActive()
        }

        private func finish(task: URLSessionTask, sample: NetworkSample) {
            if !isCaptureNetworkEnabled() {
                return
            }
            var snapshotsData: [Any] = []

            let requestsData = [sample.toDict()]
            let payloadData: [String: Any] = ["requests": requestsData]
            let pluginData: [String: Any] = ["plugin": "rrweb/network@1", "payload": payloadData]

            let data: [String: Any] = ["type": 6, "data": pluginData, "timestamp": sample.timeOrigin.toMillis()]
            snapshotsData.append(data)

            PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData])

            tasksLock.withLock {
                let _ = samplesByTask.removeValue(forKey: task)
            }
        }

        func finishAll() {
            var completedTasks: [URLSessionTask: NetworkSample] = [:]
            tasksLock.withLock {
                for item in samplesByTask {
                    if item.key.state == .completed {
                        completedTasks[item.key] = item.value
                    }
                }
            }

            for item in completedTasks {
                finish(task: item.key, sample: item.value)
            }
        }

        func stop() {
            tasksLock.withLock {
                samplesByTask.removeAll()
            }
        }
    }
#endif
