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
            retriableStatusCodes: [429, 500, 502, 503, 504],
            redirectIsRetriable: true
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
            retriableStatusCodes: [429, 500, 502, 503, 504],
            redirectIsRetriable: true
        )
    }
}

extension QueueEndpoint where Record == PostHogLogRecord {
    /// `/i/v1/logs` OTLP/JSON endpoint. Retriable set covers `408`, `429`,
    /// and all 5xx; 3xx redirects are not retriable.
    static func logs(
        api: PostHogApi,
        resourceAttributes: @escaping () -> [String: Any]
    ) -> QueueEndpoint<PostHogLogRecord> {
        // 408, 429, and all 5xx are retriable for logs.
        var retriable: Set<Int> = [408, 429]
        for code in 500 ... 599 {
            retriable.insert(code)
        }

        return QueueEndpoint<PostHogLogRecord>(
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
            retriableStatusCodes: retriable,
            redirectIsRetriable: false
        )
    }
}
