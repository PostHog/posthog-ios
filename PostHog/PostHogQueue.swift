//
//  PostHogQueue.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

/**
 # Queue

 The queue uses File persistence. This allows us to
 1. Only send events when we have a network connection
 2. Ensure that we can survive app closing or offline situations
 3. Not hold too much in memory

 */

class PostHogQueue {
    enum PostHogApiEndpoint: Int {
        case batch
        case snapshot
    }

    private let config: PostHogConfig
    private let api: PostHogApi
    private var paused: Bool = false
    private let pausedLock = NSLock()
    private var pausedUntil: Date?
    private var retryCount: TimeInterval = 0
    #if !os(watchOS)
        private let reachability: Reachability?
    #endif

    private var isFlushing = false
    private let isFlushingLock = NSLock()
    private var timer: Timer?
    private let timerLock = NSLock()
    private let endpoint: PostHogApiEndpoint
    private let dispatchQueue: DispatchQueue

    /// Internal, used for testing
    var depth: Int {
        fileQueue.depth
    }

    private let fileQueue: PostHogFileBackedQueue

    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ endpoint: PostHogApiEndpoint, _ reachability: Reachability?) {
            self.config = config
            self.api = api
            self.reachability = reachability
            self.endpoint = endpoint

            switch endpoint {
            case .batch:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue), oldQueue: storage.url(forKey: .oldQeueue))
                dispatchQueue = DispatchQueue(label: "com.posthog.Queue", target: .global(qos: .utility))
            case .snapshot:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .replayQeueue))
                dispatchQueue = DispatchQueue(label: "com.posthog.ReplayQueue", target: .global(qos: .utility))
            }
        }
    #else
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ endpoint: PostHogApiEndpoint) {
            self.config = config
            self.api = api
            self.endpoint = endpoint

            switch endpoint {
            case .batch:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue), oldQueue: storage.url(forKey: .oldQeueue))
                dispatchQueue = DispatchQueue(label: "com.posthog.Queue", target: .global(qos: .utility))
            case .snapshot:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .replayQeueue))
                dispatchQueue = DispatchQueue(label: "com.posthog.ReplayQueue", target: .global(qos: .utility))
            }
        }
    #endif

    private func eventHandler(_ payload: PostHogConsumerPayload) {
        hedgeLog("Sending batch of \(payload.events.count) events to PostHog")

        switch endpoint {
        case .batch:
            api.batch(events: payload.events) { result in
                self.handleResult(result, payload)
            }
        case .snapshot:
            api.snapshot(events: payload.events) { result in
                self.handleResult(result, payload)
            }
        }
    }

    private func handleResult(_ result: PostHogBatchUploadInfo, _ payload: PostHogConsumerPayload) {
        // -1 means its not anything related to the API but rather network or something else, so we try again
        let statusCode = result.statusCode ?? -1

        var shouldRetry = false
        if 300 ... 399 ~= statusCode || statusCode == -1 {
            shouldRetry = true
        }

        // TODO: https://github.com/PostHog/posthog-android/pull/130
        // fix: reduce batch size if API returns 413

        if shouldRetry {
            retryCount += 1
            let delay = min(retryCount * retryDelay, maxRetryDelay)
            pauseFor(seconds: delay)
            hedgeLog("Pausing queue consumption for \(delay) seconds due to \(retryCount) API failure(s).")
        } else {
            retryCount = 0
        }

        payload.completion(!shouldRetry)
    }

    func start(disableReachabilityForTesting: Bool,
               disableQueueTimerForTesting: Bool)
    {
        if !disableReachabilityForTesting {
            // Setup the monitoring of network status for the queue
            #if !os(watchOS)
                reachability?.whenReachable = { reachability in
                    self.pausedLock.withLock {
                        if self.config.dataMode == .wifi, reachability.connection != .wifi {
                            hedgeLog("Queue is paused because its not in WiFi mode")
                            self.paused = true
                        } else {
                            self.paused = false
                        }
                    }

                    // Always trigger a flush when we are on wifi
                    if reachability.connection == .wifi {
                        if !self.isFlushing {
                            self.flush()
                        }
                    }
                }

                reachability?.whenUnreachable = { _ in
                    self.pausedLock.withLock {
                        hedgeLog("Queue is paused because network is unreachable")
                        self.paused = true
                    }
                }

                do {
                    try reachability?.startNotifier()
                } catch {
                    hedgeLog("Error: Unable to monitor network reachability: \(error)")
                }
            #endif
        }

        if !disableQueueTimerForTesting {
            timerLock.withLock {
                DispatchQueue.main.async {
                    self.timer = Timer.scheduledTimer(withTimeInterval: self.config.flushIntervalSeconds, repeats: true, block: { _ in
                        if !self.isFlushing {
                            self.flush()
                        }
                    })
                }
            }
        }
    }

    /// Internal, used for testing
    func clear() {
        fileQueue.clear()
    }

    func stop() {
        timerLock.withLock {
            timer?.invalidate()
            timer = nil
        }
    }

    func flush() {
        if !canFlush() {
            return
        }

        take(config.maxBatchSize) { payload in
            if !payload.events.isEmpty {
                self.eventHandler(payload)
            } else {
                // there's nothing to be sent
                payload.completion(true)
            }
        }
    }

    private func flushIfOverThreshold() {
        if fileQueue.depth >= config.flushAt {
            flush()
        }
    }

    func add(_ event: PostHogEvent) {
        if fileQueue.depth >= config.maxQueueSize {
            hedgeLog("Queue is full, dropping oldest event")
            // first is always oldest
            fileQueue.delete(index: 0)
        }

        var data: Data?
        do {
            data = try JSONSerialization.data(withJSONObject: event.toJSON())
        } catch {
            hedgeLog("Tried to queue unserialisable PostHogEvent \(error)")
            return
        }

        fileQueue.add(data!)
        hedgeLog("Queued event '\(event.event)'. Depth: \(fileQueue.depth)")
        flushIfOverThreshold()
    }

    private func take(_ count: Int, completion: @escaping (PostHogConsumerPayload) -> Void) {
        dispatchQueue.async {
            self.isFlushingLock.withLock {
                if self.isFlushing {
                    return
                }
                self.isFlushing = true
            }

            let items = self.fileQueue.peek(count)

            var processing = [PostHogEvent]()

            for item in items {
                // each element is a PostHogEvent if fromJSON succeeds
                guard let event = PostHogEvent.fromJSON(item) else {
                    continue
                }
                processing.append(event)
            }

            completion(PostHogConsumerPayload(events: processing) { success in
                if success, items.count > 0 {
                    self.fileQueue.pop(items.count)
                    hedgeLog("Completed!")
                }

                self.isFlushingLock.withLock {
                    self.isFlushing = false
                }
            })
        }
    }

    private func pauseFor(seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
    }

    private func canFlush() -> Bool {
        if isFlushing {
            hedgeLog("Already flushing")
            return false
        }

        if paused {
            // We don't flush data if the queue is paused
            hedgeLog("The queue is paused due to the reachability check")
            return false
        }

        if pausedUntil != nil, pausedUntil! > Date() {
            // We don't flush data if the queue is temporarily paused
            hedgeLog("The queue is paused until `\(pausedUntil!)`")
            return false
        }

        return true
    }
}
