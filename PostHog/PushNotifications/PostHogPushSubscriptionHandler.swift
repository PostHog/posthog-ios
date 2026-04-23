//
//  PostHogPushSubscriptionHandler.swift
//  PostHog
//
//  Created on 23/04/2026.
//

import Foundation

/// Sends push notification device tokens to PostHog and retries on failure.
final class PostHogPushSubscriptionHandler {
    private let api: PostHogApi
    private let storage: PostHogStorage
    private let distinctIdProvider: () -> String

    init(
        _ api: PostHogApi,
        _ storage: PostHogStorage,
        _ distinctIdProvider: @escaping () -> String
    ) {
        self.api = api
        self.storage = storage
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

        // Persist so we can retry if the request fails or the device is offline
        storage.setDictionary(forKey: .pushSubscription, contents: [
            "distinctId": distinctId,
            "deviceToken": deviceToken,
            "appId": appId,
        ])

        api.pushSubscription(distinctId: distinctId, deviceToken: deviceToken, appId: appId) { [weak self] success in
            if success {
                hedgeLog("Sent push subscription to PostHog.")
                self?.storage.remove(key: .pushSubscription)
            } else {
                hedgeLog("Failed to send push subscription to PostHog. Will retry on next flush.")
            }
        }
    }

    /// Retries sending a persisted push subscription if one exists.
    func retryIfNeeded() {
        guard let data = storage.getDictionary(forKey: .pushSubscription) as? [String: String],
              let distinctId = data["distinctId"],
              let deviceToken = data["deviceToken"],
              let appId = data["appId"]
        else {
            return
        }

        api.pushSubscription(distinctId: distinctId, deviceToken: deviceToken, appId: appId) { [weak self] success in
            if success {
                hedgeLog("Sent push subscription to PostHog (retry).")
                self?.storage.remove(key: .pushSubscription)
            } else {
                hedgeLog("Retry of push subscription failed. Will retry on next flush.")
            }
        }
    }
}
