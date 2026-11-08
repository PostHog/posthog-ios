//
//  PostHogVersion.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

// if you change this, check if the script scripts/bump-version.sh still works
/// Current SDK version string.
///
/// - Warning: This is intended for SDK internals and integrations. Application code should not mutate it.
@_spi(PostHogInternal) public var postHogVersion = "3.94.0"

/// Default SDK name reported by the native iOS SDK.
let postHogiOSSdkName = "posthog-ios"

/// SDK name included in captured event context.
///
/// - Warning: This is intended for SDK internals and wrapper SDKs. Application code should not mutate it.
@_spi(PostHogInternal) public var postHogSdkName = postHogiOSSdkName

/// SDK identity hooks for wrapper SDKs.
public extension PostHogSDK {
    /// Sets the SDK name and version reported with every request and event, for wrapper SDKs that
    /// can't assign `postHogSdkName`/`postHogVersion` directly (Objective-C and Kotlin Multiplatform).
    /// Call it before `setup`.
    ///
    /// - Warning: This is intended for wrapper SDKs. Application code should not call it.
    @_spi(PostHogInternal) @objc(setSdkName:version:)
    static func setSdkName(_ name: String, version: String) {
        postHogSdkName = name
        postHogVersion = version
    }
}
