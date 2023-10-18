//
//  PostHogExtensions.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

/**
 # Notifications

 This helper module encapsulates all notifications that we trigger from within the SDK.

 */

public extension PostHog {
    static let didStartNotification = Notification.Name("PostHogDidStart") // object: nil
    static let didStartRecordingNotification = Notification.Name("PostHogDidStartRecording") // object: nil
    static let didResetSessionNotification = Notification.Name("PostHogDidResetSession") // object: String
    static let didReceiveFeatureFlags = Notification.Name("PostHogDidReceiveFeatureFlags") // object: nil
}
