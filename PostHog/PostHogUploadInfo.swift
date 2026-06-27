//
//  PostHogUploadInfo.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

struct PostHogUploadInfo {
    let statusCode: Int?
    let error: Error?
    let retryAfter: TimeInterval?

    init(statusCode: Int?, error: Error?, retryAfter: TimeInterval? = nil) {
        self.statusCode = statusCode
        self.error = error
        self.retryAfter = retryAfter
    }
}
