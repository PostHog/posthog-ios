//
//  QueueEndpoint+Factories.swift
//  PostHog
//

import Foundation

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
            // `/batch` retries 429, the listed 5xx, plus 3xx redirects.
            isRetriableStatusCode: { code in
                code == 429
                    || [500, 502, 503, 504].contains(code)
                    || (300 ... 399).contains(code)
            }
        )
    }

    /// `/snapshot` endpoint for session-replay snapshots. Same retry shape
    /// as `/batch` — they share `PostHogQueue.handleResult` exactly.
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
            isRetriableStatusCode: { code in
                code == 429
                    || [500, 502, 503, 504].contains(code)
                    || (300 ... 399).contains(code)
            }
        )
    }
}

extension QueueEndpoint where Record == PostHogLogRecord {
    /// `/i/v1/logs` OTLP/JSON endpoint. Retries `408`, `429`, and all 5xx;
    /// 3xx redirects are not retriable.
    static func logs(
        api: PostHogApi,
        resourceAttributes: @escaping () -> [String: Any]
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
                    resourceAttributes: resourceAttributes(),
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
