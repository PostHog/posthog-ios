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

    var deleteFiles = false
    defer {
        if deleteFiles {
            try? FileManager.default.removeItem(at: oldQueue)
        }
    }

    do {
        let data = try Data(contentsOf: oldQueue)
        let array = try JSONSerialization.jsonObject(with: data) as? [Any]

        if array == nil {
            deleteFiles = true
            return
        }

        for item in array! {
            guard let event = item as? [String: Any] else {
                continue
            }
            let timestamp = event["timestamp"] as? String ?? toISO8601String(Date())

            let timestampDate = toISO8601Date(timestamp) ?? Date()

            let filename = "\(timestampDate.timeIntervalSince1970)"

            let contents = try? JSONSerialization.data(withJSONObject: event)

            if contents == nil {
                continue
            }
            try? contents!.write(to: queue.appendingPathComponent(filename))

            deleteFiles = true
        }
    } catch {
        deleteFiles = false
    }
}
