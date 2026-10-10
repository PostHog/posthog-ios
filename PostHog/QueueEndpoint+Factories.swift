//
//  QueueEndpoint+Factories.swift
//  PostHog
//

import Foundation

/// Retry policy shared by `/batch` (events fallback) and `/snapshot` (replay): 408, 429,
/// the listed 5xx, plus 3xx redirects.
private func isEventsRetriableStatusCode(_ code: Int) -> Bool {
    [408, 429, 500, 502, 503, 504].contains(code)
        || (300 ... 399).contains(code)
}

/// Capture V1 retry policy: 408 and the listed 5xx. Everything else, including
/// 429 and 3xx, is terminal; 413 is handled by the queue's batch halving.
func isCaptureV1RetriableStatusCode(_ code: Int) -> Bool {
    [408, 500, 502, 503, 504].contains(code)
}

extension QueueEndpoint where Record == PostHogEvent {
    /// Analytics events endpoint: capture V1 (`/i/v1/analytics/events`), or
    /// `/batch` after V1 returned 404 this session.
    static func batch(api: PostHogApi) -> QueueEndpoint<PostHogEvent> {
        QueueEndpoint<PostHogEvent>(
            storageKey: .queue,
            oldStorageKeys: [.oldQueueFolder, .oldQueuePlist],
            dispatchQueueLabel: "com.posthog.Queue",
            initialCap: { $0.maxBatchSize },
            initialFlushAt: { $0.flushAt },
            maxQueueSize: { $0.maxQueueSize },
            flushIntervalSeconds: { $0.flushIntervalSeconds },
            rateCapMax: { _ in 0 },
            rateCapWindowSeconds: { _ in 0 },
            encode: { event in toJSONData(event.toJSON()) },
            decode: { data in PostHogEvent.fromJSON(data) },
            describe: { event in "event '\(event.event)'" },
            recordId: { event in event.uuid.postHogUuidString },
            send: { events, completion in
                api.captureV1(events: events, completion: completion)
            },
            isRetriableStatusCode: { code in
                // The /batch fallback keeps the /batch policy. Remove with /batch.
                api.usesCaptureV1 ? isCaptureV1RetriableStatusCode(code) : isEventsRetriableStatusCode(code)
            }
        )
    }

    /// `/snapshot` endpoint for session-replay snapshots. Shares its retry
    /// policy with `/batch`.
    static func snapshot(api: PostHogApi) -> QueueEndpoint<PostHogEvent> {
        QueueEndpoint<PostHogEvent>(
            storageKey: .replayQeueue,
            oldStorageKeys: [.oldReplayQueue],
            dispatchQueueLabel: "com.posthog.ReplayQueue",
            initialCap: { $0.maxBatchSize },
            initialFlushAt: { $0.flushAt },
            maxQueueSize: { $0.maxQueueSize },
            flushIntervalSeconds: { $0.flushIntervalSeconds },
            rateCapMax: { _ in 0 },
            rateCapWindowSeconds: { _ in 0 },
            encode: { event in toJSONData(event.toJSON()) },
            decode: { data in PostHogEvent.fromJSON(data) },
            describe: { _ in "snapshot" },
            canBatchTogether: { first, next in
                // Capture attributes the entire request to the first snapshot.
                first.distinctId == next.distinctId
                    && (first.properties["$session_id"] as? String) == (next.properties["$session_id"] as? String)
            },
            send: { events, completion in
                api.snapshot(events: events, completion: completion)
            },
            isRetriableStatusCode: isEventsRetriableStatusCode
        )
    }
}

extension QueueEndpoint where Record == PostHogLogRecord {
    /// `/i/v1/logs` OTLP/JSON endpoint. Retries `408`, `429`, and all 5xx;
    /// 3xx redirects are not retriable.
    ///
    /// `resourceAttributes` is taken by value — the caller snapshots
    /// `config.logs` once at SDK setup and passes the merged dict here, so
    /// post-setup mutations of `config.logs.resourceAttributes` are not
    /// honored (matches the doc contract on `PostHogLogsConfig`).
    static func logs(
        api: PostHogApi,
        resourceAttributes: [String: Any]
    ) -> QueueEndpoint<PostHogLogRecord> {
        // Snapshot the SDK version once so it can't disagree with the
        // `telemetry.sdk.version` we baked into `resourceAttributes`.
        let scopeVersion = postHogVersion
        return QueueEndpoint<PostHogLogRecord>(
            storageKey: .logsQueue,
            oldStorageKeys: [],
            dispatchQueueLabel: "com.posthog.LogsQueue",
            initialCap: { $0.logs.maxBatchSize },
            initialFlushAt: { $0.logs.flushAt },
            maxQueueSize: { $0.logs.maxBufferSize },
            flushIntervalSeconds: { $0.logs.flushIntervalSeconds },
            // Clamp to 0; a negative window would make `elapsed >= window`
            // trivially true and reset the counter on every call.
            rateCapMax: { max(0, $0.logs.rateCapMaxLogs) },
            rateCapWindowSeconds: { max(0, $0.logs.rateCapWindowSeconds) },
            encode: { record in toJSONData(record.toStorageJSON()) },
            decode: { data in
                guard let json = fromJSONData(data) else { return nil }
                return PostHogLogRecord.fromStorageJSON(json)
            },
            describe: { _ in "log" },
            send: { records, completion in
                let payload = PostHogLogsOTLP.buildPayload(
                    records: records,
                    resourceAttributes: resourceAttributes,
                    scopeVersion: scopeVersion
                )
                api.logs(payload: payload, completion: completion)
            },
            isRetriableStatusCode: { code in
                code == 408 || code == 429 || (500 ... 599).contains(code)
            }
        )
    }
}
