//
//  QueueEndpoint+Factories.swift
//  PostHog
//

import Foundation

extension QueueEndpoint where Record == PostHogEvent {
    /// `/batch` endpoint for analytics events. Cap stays put on 2xx and stays
    /// at 1 after a poison drop — matches posthog-android.
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
            redirectIsRetriable: true,
            capAfterSuccess: { cap, _ in cap },
            capAfterPoisonDrop: { _, _ in 1 },
            capAfterDropAll: { cap, _ in cap }
        )
    }

    /// `/snapshot` endpoint for session-replay snapshots. Same retry / cap
    /// shape as `/batch` — they share `PostHogQueue.handleResult` exactly.
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
            redirectIsRetriable: true,
            capAfterSuccess: { cap, _ in cap },
            capAfterPoisonDrop: { _, _ in 1 },
            capAfterDropAll: { cap, _ in cap }
        )
    }
}

extension QueueEndpoint where Record == PostHogLogRecord {
    /// `/i/v1/logs` OTLP/JSON endpoint. Wider retriable set than events
    /// (includes `408` and all 5xx). Cap ramps `+1` on each healthy send and
    /// resets to `max` after a poison-drop, since the oversized record is gone
    /// and remaining records fit normally.
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
            // Logs queue uses the cap itself as the flush threshold — there is
            // no separate `flushAt`. Initialising both equal keeps the
            // generic queue's `flushIfOverThreshold` behaving identically.
            initialFlushAt: { $0.logs.maxBatchSize },
            maxQueueSize: { $0.logs.maxBufferSize },
            flushIntervalSeconds: { $0.logs.flushIntervalSeconds },
            encode: { record in toJSONData(record.toStorageJSON()) },
            decode: { data in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
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
            redirectIsRetriable: false,
            capAfterSuccess: { cap, max in min(cap + 1, max) },
            capAfterPoisonDrop: { _, max in max },
            capAfterDropAll: { _, max in max }
        )
    }
}
