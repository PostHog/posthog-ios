//
//  Test.swift
//  PostHogExample
//
//  Created by Manoel Aranda Neto on 02.11.23.
//

import Foundation

import PostHog

class Test {
    func test() {
//        PostHog.capture("user_signed_up", properties = mapOf("is_free_trial" to true))
//        // check out the `userProperties`, `userPropertiesSetOnce` and `groupProperties` parameters.
        
        let apiKey = ""

        let config = PostHogConfig(apiKey: apiKey)
        // it's enabled by default
        config.captureScreenViews = true
        PostHogSDK.shared.setup(config)
        
        // Or manually
        PostHogSDK.shared.capture("Dashboard", properties: ["is_free_trial": true])
    }
}
