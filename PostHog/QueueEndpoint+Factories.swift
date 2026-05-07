//
//  QueueEndpoint+Factories.swift
//  PostHog
//

import Foundation

/// Retry policy shared by `/batch` (events) and `/snapshot` (replay): 429,
/// the listed 5xx, plus 3xx redirects.
private func isEventsRetriableStatusCode(_ code: Int) -> Bool {
    code == 429
        || [500, 502, 503, 504].contains(code)
        || (300 ... 399).contains(code)
}

extension QueueEndpoint where Record == PostHogEvent {
    /// `/batch` endpoint for analytics events.
    static func batch(api: PostHogApi) -> QueueEndpoint<PostHogEvent> {
        QueueEndpoint<PostHogEvent>(
            storageKey: .queue,
            oldStorageKeys: [.oldQueueFolder, .oldQueuePlist],
            dispatchQueueLabel: "com.posthog.Queue",
            initialCap: { $0.maxBatchSize },
            initialFlushAt: { $0.flushAt },
            maxQueueSize: { $0.maxQueueSize },
            flushIntervalSeconds: { $0.flushIntervalSeconds },
            encode: { event in toJSONData(event.toJSON()) },
            decode: { data in PostHogEvent.fromJSON(data) },
            send: { events, completion in
                api.batch(events: events, completion: completion)
            },
            isRetriableStatusCode: isEventsRetriableStatusCode
        )
    }

    /// `/snapshot` endpoint for session-replay snapshots. Shares its retry
    /// policy with `/batch`.
    static func snapshot(api: PostHogApi) -> QueueEndpoint<PostHogEvent> {
        QueueEndpoint<PostHogEvent>(
            storageKey: .replayQeueue,
            oldStorageKeys: [],
            dispatchQueueLabel: "com.posthog.ReplayQueue",
            initialCap: { $0.maxBatchSize },
            initialFlushAt: { $0.flushAt },
            maxQueueSize: { $0.maxQueueSize },
            flushIntervalSeconds: { $0.flushIntervalSeconds },
            encode: { event in toJSONData(event.toJSON()) },
            decode: { data in PostHogEvent.fromJSON(data) },
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
        QueueEndpoint<PostHogLogRecord>(
            storageKey: .logsQueue,
            oldStorageKeys: [],
            dispatchQueueLabel: "com.posthog.LogsQueue",
            initialCap: { $0.logs.maxBatchSize },
            initialFlushAt: { $0.logs.flushAt },
            maxQueueSize: { $0.logs.maxBufferSize },
            flushIntervalSeconds: { $0.logs.flushIntervalSeconds },
            encode: { record in toJSONData(record.toStorageJSON()) },
            decode: { data in
                guard let json = fromJSONData(data) else { return nil }
                return PostHogLogRecord.fromStorageJSON(json)
            },
            send: { records, completion in
                let payload = PostHogLogsOTLP.buildPayload(
                    records: records,
                    resourceAttributes: resourceAttributes,
                    scopeVersion: postHogVersion
                )
                api.logs(payload: payload, completion: completion)
            },
            isRetriableStatusCode: { code in
                code == 408 || code == 429 || (500 ... 599).contains(code)
            }
        )
    }
}
