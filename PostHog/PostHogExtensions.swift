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

/// Notifications emitted by the PostHog SDK.
public extension PostHogSDK {
    /// Posted on the main queue after `setup(_:)` finishes successfully.
    ///
    /// The notification object is `nil`.
    @objc static let didStartNotification = Notification.Name("PostHogDidStart") // object: nil
}
