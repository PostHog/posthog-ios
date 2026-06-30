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

    /// Posted after a feature flag reload finishes and cached flags are updated.
    ///
    /// The notification object is `nil`.
    @objc static let didReceiveFeatureFlags = Notification.Name("PostHogDidReceiveFeatureFlags") // object: nil
}

extension PostHogSDK {
    /// Posted (synchronously, on the calling thread) right after the person properties used
    /// for feature flag evaluation change — via `identify`, `setPersonProperties`, or
    /// `setPersonPropertiesForFlags`. Used internally to re-resolve the language of a survey
    /// that is currently on screen so it follows updates to the user's `language` property.
    ///
    /// The notification object is `nil`.
    static let personPropertiesForFlagsDidChange = Notification.Name("PostHogPersonPropertiesForFlagsDidChange") // object: nil
}
