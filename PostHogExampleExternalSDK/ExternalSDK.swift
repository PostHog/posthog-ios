//
//  ExternalSDK.swift
//  ExternalSDK
//
//  Created by Yiannis Josephides on 24/01/2025.
//

import Foundation
import PostHog

public final class MyExternalSDK {
    public static let shared = MyExternalSDK()

    private init() {
        let config = PostHogConfig(
            apiKey: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )

        config.captureScreenViews = true
        config.captureApplicationLifecycleEvents = true
        config.debug = true
        config.sendFeatureFlagEvent = false
        config.sessionReplay = true
        config.sessionReplayConfig.maskAllImages = false
        config.sessionReplayConfig.maskAllTextInputs = false
        config.sessionReplayConfig.maskAllSandboxedViews = false

        PostHogSDK.shared.setup(config)
    }

    public func track(event: String) {
        PostHogSDK.shared.capture("An Event From ExternalSDK - \(event)")
    }
}
