//
//  PostHogLegacyQueue.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation

// Migrates the Old Queue (v2) to the new Queue (v3)
func migrateOldQueue(queue: URL, oldQueue: URL) {
    if !FileManager.default.fileExists(atPath: oldQueue.path) {
        return
    }

    defer {
        deleteSafely(oldQueue)
    }

    do {
        let data = try Data(contentsOf: oldQueue)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            hedgeLog("Failed to migrate queue: invalid data format")
            return
        }

        for item in array {
            guard var event = item as? [String: Any] else {
                continue
            }
            let eventName = event["event"] as? String ?? ""
            if let properties = event["properties"] as? [String: Any] {
                event["properties"] = PostHogEvent.serializedProperties(properties, event: eventName)
            }
            // v2 stored person properties outside the properties container.
            if let setProperties = event["$set"] as? [String: Any] {
                event["$set"] = PostHogEvent.serializedProperties(setProperties, event: "")
            }
            let timestamp = event["timestamp"] as? String ?? toISO8601String(Date())

            let timestampDate = toISO8601Date(timestamp) ?? Date()

            let filename = "\(timestampDate.timeIntervalSince1970)"

            let contents = try JSONSerialization.data(withJSONObject: event)

            try contents.write(to: queue.appendingPathComponent(filename))
        }
    } catch {
        hedgeLog("Failed to migrate queue \(error)")
    }
}
