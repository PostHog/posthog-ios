//
//  PostHogPersonProfiles.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 09.09.24.
//

import Foundation

/// Determines the behavior for processing user profiles.
/// - `never`: We won't process persons for any event. This means that anonymous users will not be merged once
/// they sign up or login, so you lose the ability to create funnels that track users from anonymous to identified.
/// All events (including `$identify`) will be sent with `$process_person_profile: False`.
/// - `always`: We will process persons data for all events.
/// - `identifiedOnly`: (default): we will only process persons when you call `identify`, `alias`, and `group`, Anonymous users won't get person profiles.
@objc(PostHogPersonProfiles) public enum PostHogPersonProfiles: Int {
    case never
    case always
    case identifiedOnly
}
