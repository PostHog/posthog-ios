//
//  PostHogConsumerPayload.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

struct PostHogConsumerPayload {
    let events: [PostHogEvent]
    let completion: (Bool) -> Void
}
