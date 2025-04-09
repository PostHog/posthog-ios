//
//  Optional+Util.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/01/2025.
//

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
