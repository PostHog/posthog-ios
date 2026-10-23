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
    /// Record IDs a 2xx response asked to retry (capture V1 per-event results).
    /// The rest of the batch is delivered. `nil` or empty means the whole batch
    /// shares `statusCode`'s outcome.
    let retryRecordIds: Set<String>?

    init(statusCode: Int?, error: Error?, retryAfter: TimeInterval? = nil, retryRecordIds: Set<String>? = nil) {
        self.statusCode = statusCode
        self.error = error
        self.retryAfter = retryAfter
        self.retryRecordIds = retryRecordIds
    }
}
