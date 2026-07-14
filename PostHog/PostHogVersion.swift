//
//  PostHogVersion.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

// if you change this, make sure to also change it in the podspec and check if the script scripts/bump-version.sh still works
/// Current SDK version string.
///
/// - Warning: This is intended for SDK internals and integrations. Application code should not mutate it.
public var postHogVersion = "3.64.7"

/// Default SDK name reported by the native iOS SDK.
public let postHogiOSSdkName = "posthog-ios"

/// SDK name included in captured event context.
///
/// - Warning: This is intended for SDK internals and wrapper SDKs. Application code should not mutate it.
public var postHogSdkName = postHogiOSSdkName
