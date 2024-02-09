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
 3. Not hold too much in mempory

 */

class PostHogQueue {
    private let config: PostHogConfig
    private let storage: PostHogStorage
    private let api: PostHogApi
    private var paused: Bool = false
    private var pausedLock = NSLock()
    private var pausedUntil: Date?
    private var retryCount: TimeInterval = 0
    #if !os(watchOS)
        private let reachability: Reachability?
    #endif

    private var isFlushing = false
    private let isFlushingLock = NSLock()
    private var timer: Timer?
    private let timerLock = NSLock()

    private let dispatchQueue = DispatchQueue(label: "com.posthog.Queue", target: .global(qos: .utility))

    var depth: Int {
        fileQueue.depth
    }

    private let fileQueue: PostHogFileBackedQueue

    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ reachability: Reachability?) {
            self.config = config
            self.storage = storage
            self.api = api
            self.reachability = reachability
            fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue), oldQueue: storage.url(forKey: .oldQeueue))
        }
    #else
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi) {
            self.config = config
            self.storage = storage
            self.api = api
            fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue), oldQueue: storage.url(forKey: .oldQeueue))
        }
    #endif

    private func eventHandler(_ payload: PostHogConsumerPayload) {
        hedgeLog("Sending batch of \(payload.events.count) events to PostHog")

        api.batch(events: payload.events) { result in
            // -1 means its not anything related to the API but rather network or something else, so we try again
            let statusCode = result.statusCode ?? -1

            var shouldRetry = false
            if 300 ... 399 ~= statusCode || statusCode == -1 {
                shouldRetry = true
            }

            if shouldRetry {
                self.retryCount += 1
                let delay = min(self.retryCount * retryDelay, maxRetryDelay)
                self.pauseFor(seconds: delay)
                hedgeLog("Pausing queue consumption for \(delay) seconds due to \(self.retryCount) API failure(s).")
            } else {
                self.retryCount = 0
            }

            payload.completion(!shouldRetry)
        }
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
                timer = Timer.scheduledTimer(withTimeInterval: config.flushIntervalSeconds, repeats: true, block: { _ in
                    if !self.isFlushing {
                        self.flush()
                    }
                })
            }
        }
    }

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
            hedgeLog("Already flushing")
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
            return false
        }

        if paused {
            // We don't flush data if the queue is paused
            return false
        }

        if pausedUntil != nil, pausedUntil! > Date() {
            // We don't flush data if the queue is temporarily paused
            return false
        }

        return true
    }
}
