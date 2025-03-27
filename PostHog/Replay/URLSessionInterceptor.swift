/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

    import Foundation

    class URLSessionInterceptor {
        private weak var postHog: PostHogSDK?

        private let tasksLock = NSLock()

        init(_ postHog: PostHogSDK) {
            self.postHog = postHog
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

            let date = now()

            guard let sessionId = PostHogSessionManager.shared.getSessionId(at: date) else {
                return
            }

            queue.async {
                let sample = NetworkSample(
                    sessionId: sessionId,
                    timeOrigin: date,
                    url: url.absoluteString
                )

                self.tasksLock.withLock {
                    self.samplesByTask[task] = sample
                }

                self.finishAll()
            }
        }

        /// Notifies the `URLSessionTask` completion.
        /// This method should be called as soon as the task was completed.
        /// - Parameter task: the task object obtained from `URLSession`.
        /// - Parameter error: optional `Error` if the task completed with error.
        func taskCompleted(task: URLSessionTask, error _: Error?) {
            if !isCaptureNetworkEnabled() {
                return
            }

            let date = Date()

            queue.async {
                var sampleTask: NetworkSample?
                self.tasksLock.withLock {
                    sampleTask = self.samplesByTask[task]
                }

                guard var sample = sampleTask else {
                    return
                }

                self.finish(task: task, sample: &sample, date: date)

                self.finishAll()
            }
        }

        private func finish(task: URLSessionTask, sample: inout NetworkSample, date: Date? = nil) {
            // only safe guard, should not happen
            guard let request = task.originalRequest else {
                tasksLock.withLock {
                    _ = samplesByTask.removeValue(forKey: task)
                }
                return
            }

            let responseStatusCode = urlResponseStatusCode(response: task.response)

            if responseStatusCode != -1 {
                sample.responseStatus = responseStatusCode
            }

            sample.httpMethod = request.httpMethod
            sample.initiatorType = "fetch"
            // instrumented requests that dont use the completion handler wont have the duration set
            if let date = date {
                sample.duration = (date.toMillis() - sample.timeOrigin.toMillis())
            }

            // the UI special case if the transferSize is 0 as coming from cache
            let transferSize = Int64(request.httpBody?.count ?? 0) + (task.response?.expectedContentLength ?? 0)
            if transferSize > 0 {
                sample.decodedBodySize = transferSize
            }

            finish(task: task, sample: sample)
        }

        // MARK: - Private

        private func urlResponseStatusCode(response: URLResponse?) -> Int {
            if let urlResponse = response as? HTTPURLResponse {
                return urlResponse.statusCode
            }
            return -1
        }

        private func isCaptureNetworkEnabled() -> Bool {
            guard let postHog else { return false }
            return postHog.config.sessionReplayConfig.captureNetworkTelemetry && postHog.isSessionReplayActive()
        }

        private func finish(task: URLSessionTask, sample: NetworkSample) {
            if let postHog {
                let timestamp = sample.timeOrigin

                var snapshotsData: [Any] = []

                let requestsData = [sample.toDict()]
                let payloadData: [String: Any] = ["requests": requestsData]
                let pluginData: [String: Any] = ["plugin": "rrweb/network@1", "payload": payloadData]

                let data: [String: Any] = [
                    "type": 6,
                    "data": pluginData,
                    "timestamp": timestamp.toMillis(),
                ]
                snapshotsData.append(data)

                postHog.capture(
                    "$snapshot",
                    properties: [
                        "$snapshot_source": "mobile",
                        "$snapshot_data": snapshotsData,
                        "$session_id": sample.sessionId,
                    ],
                    timestamp: sample.timeOrigin
                )
            }

            tasksLock.withLock {
                _ = samplesByTask.removeValue(forKey: task)
            }
        }

        private func finishAll() {
            var completedTasks: [URLSessionTask: NetworkSample] = [:]
            tasksLock.withLock {
                for item in samplesByTask where item.key.state == .completed {
                    completedTasks[item.key] = item.value
                }
            }

            for item in completedTasks {
                var value = item.value
                finish(task: item.key, sample: &value)
            }
        }

        func stop() {
            tasksLock.withLock {
                samplesByTask.removeAll()
            }
        }
    }
#endif
