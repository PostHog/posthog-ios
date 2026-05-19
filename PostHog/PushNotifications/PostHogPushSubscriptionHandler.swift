//
//  PostHogPushSubscriptionHandler.swift
//  PostHog
//
//  Created on 23/04/2026.
//

import Foundation

/// Sends push notification device tokens to PostHog and retries on failure.
///
/// Retry behaviour mirrors `PostHogQueue`: linear backoff
/// (`retryCount * retryDelay`, capped at `maxRetryDelay`) with a hard limit of
/// `config.maxRetries` attempts before giving up until the next app launch.
final class PostHogPushSubscriptionHandler {
    private let api: PostHogApi
    private let storage: PostHogStorage
    private let config: PostHogConfig
    private let distinctIdProvider: () -> String

    /// Guards `retryCount`, `pausedUntil`, and `isSending`.
    private let stateLock = NSLock()
    private var retryCount: Int = 0
    private var pausedUntil: Date?
    private var isSending: Bool = false

    init(
        _ api: PostHogApi,
        _ storage: PostHogStorage,
        _ config: PostHogConfig,
        _ distinctIdProvider: @escaping () -> String
    ) {
        self.api = api
        self.storage = storage
        self.config = config
        self.distinctIdProvider = distinctIdProvider
    }

    func send(deviceToken: String) {
        let distinctId = distinctIdProvider()
        if distinctId.isEmpty {
            hedgeLog("Push subscription not sent: no distinct ID.")
            return
        }

        let appId = Bundle.main.bundleIdentifier ?? ""
        if appId.isEmpty {
            hedgeLog("Push subscription not sent: no bundle identifier found.")
            return
        }

        if deviceToken.isEmpty {
            hedgeLog("Push subscription not sent: device token is empty.")
            return
        }

        // Persist so we can retry if the request fails or the device is offline.
        storage.setDictionary(forKey: .pushSubscription, contents: [
            "deviceToken": deviceToken,
            "appId": appId,
        ])

        // Reset backoff state — a new token supersedes any previous failure.
        stateLock.withLock {
            retryCount = 0
            pausedUntil = nil
        }

        attempt(distinctId: distinctId, deviceToken: deviceToken, appId: appId)
    }

    /// Retries sending a persisted push subscription if one exists and the
    /// backoff window has elapsed.
    func retryIfNeeded() {
        guard let data = storage.getDictionary(forKey: .pushSubscription) as? [String: String],
              let deviceToken = data["deviceToken"],
              let appId = data["appId"]
        else {
            return
        }

        if let until = stateLock.withLock({ pausedUntil }), until > Date() {
            hedgeLog("Push subscription retry deferred: backoff active until \(until).")
            return
        }

        // Always use the current distinct ID so the token is linked to whoever
        // is identified now, not whoever was identified when send() was called.
        let distinctId = distinctIdProvider()
        if distinctId.isEmpty {
            hedgeLog("Push subscription retry skipped: no distinct ID.")
            return
        }

        attempt(distinctId: distinctId, deviceToken: deviceToken, appId: appId)
    }

    // MARK: - Private

    private func attempt(distinctId: String, deviceToken: String, appId: String) {
        let alreadySending = stateLock.withLock { () -> Bool in
            if isSending { return true }
            isSending = true
            return false
        }
        guard !alreadySending else {
            hedgeLog("Push subscription skipped: request already in flight.")
            return
        }

        api.pushSubscription(distinctId: distinctId, deviceToken: deviceToken, appId: appId) { [weak self] success in
            guard let self else { return }
            self.stateLock.withLock { self.isSending = false }

            if success {
                hedgeLog("Sent push subscription to PostHog.")
                self.stateLock.withLock {
                    self.retryCount = 0
                    self.pausedUntil = nil
                }
                self.storage.remove(key: .pushSubscription)
            } else {
                self.handleFailure()
            }
        }
    }

    private func handleFailure() {
        let newCount = stateLock.withLock { () -> Int in
            retryCount += 1
            return retryCount
        }

        if newCount > config.maxRetries {
            hedgeLog("Push subscription: max retries (\(config.maxRetries)) exceeded. Will retry on next app launch.")
            stateLock.withLock {
                retryCount = 0
                pausedUntil = nil
            }
            return
        }

        let delay = min(TimeInterval(newCount) * retryDelay, maxRetryDelay)
        let until = Date().addingTimeInterval(delay)
        stateLock.withLock { pausedUntil = until }
        hedgeLog("Push subscription failed (attempt \(newCount)/\(config.maxRetries)). Retrying in \(delay)s.")
    }
}
