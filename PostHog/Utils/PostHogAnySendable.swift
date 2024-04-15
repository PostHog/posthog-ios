//
//  PostHogAnySendable.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 15.04.24.
//

import Foundation

struct PostHogAnySendable<T: Sendable> {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}
