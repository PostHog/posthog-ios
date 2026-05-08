//
//  PostHogConsumerPayload.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

/// Payload handed from `PostHogQueue.take` to the send pipeline. Generic over
/// the record type so the same queue infrastructure can ship `PostHogEvent`
/// (events / replay snapshots) and `PostHogLogRecord` (logs).
struct PostHogConsumerPayload<Record> {
    let records: [Record]
    let completion: (Bool) -> Void
}
