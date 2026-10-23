//
//  PostHogTriggerGroups.swift
//  PostHog
//
//  Created on 06.10.26.
//

import Foundation

struct PostHogTriggerGroupsConfig {
    let groups: [PostHogTriggerGroup]
}

struct PostHogTriggerGroup {
    let id: String
    let name: String
    let sampleRate: Double?
    let minDurationMs: Int64?
    let conditions: PostHogTriggerConditions
}

enum PostHogTriggerMatchType {
    case any
    case all
}

struct PostHogTriggerConditions {
    let matchType: PostHogTriggerMatchType
    let events: [PostHogTriggerEvent]
    let urls: [NSRegularExpression]
    let flag: PostHogTriggerFlag?
    let properties: [PostHogTriggerPropertyFilter]
}

struct PostHogTriggerEvent {
    let name: String
    let properties: [PostHogTriggerPropertyFilter]
}

struct PostHogTriggerFlag {
    let flag: String
    let variant: String?
}

struct PostHogTriggerPropertyFilter {
    let key: String
    let type: String?
    /// The remote-config `operator` field; `operator` is a Swift keyword so it cannot be the property name.
    let filterOperator: String?
    let value: Any?
}

func parseTriggerGroupsConfig(_ sessionRecording: [String: Any]) -> PostHogTriggerGroupsConfig? {
    let version = (sessionRecording["version"] as? NSNumber)?.int64Value ?? 1
    if version != 2 { return nil }

    guard let rawGroups = sessionRecording["triggerGroups"] as? [Any] else { return nil }

    let groups = rawGroups.compactMap { raw -> PostHogTriggerGroup? in
        guard let map = raw as? [String: Any],
              let id = map["id"] as? String, !id.isEmpty
        else {
            hedgeLog("Session recording trigger group without an id was ignored.")
            return nil
        }
        return PostHogTriggerGroup(
            id: id,
            name: map["name"] as? String ?? "",
            sampleRate: (map["sampleRate"] as? NSNumber)?.doubleValue,
            minDurationMs: (map["minDurationMs"] as? NSNumber)?.int64Value,
            conditions: parseTriggerConditions(map["conditions"])
        )
    }

    if groups.isEmpty { return nil }

    return PostHogTriggerGroupsConfig(groups: groups)
}

private func parseTriggerConditions(_ conditions: Any?) -> PostHogTriggerConditions {
    let map = conditions as? [String: Any]
    return PostHogTriggerConditions(
        matchType: map?["matchType"] as? String == "any" ? .any : .all,
        events: parseTriggerEvents(map?["events"]),
        urls: parseTriggerUrls(map?["urls"]),
        flag: parseTriggerFlag(map?["flag"]),
        properties: parseTriggerPropertyFilters(map?["properties"])
    )
}

private func parseTriggerEvents(_ events: Any?) -> [PostHogTriggerEvent] {
    (events as? [Any] ?? []).compactMap { raw in
        guard let map = raw as? [String: Any],
              let name = map["name"] as? String
        else { return nil }
        return PostHogTriggerEvent(
            name: name,
            properties: parseTriggerPropertyFilters(map["properties"])
        )
    }
}

private func parseTriggerUrls(_ urls: Any?) -> [NSRegularExpression] {
    (urls as? [Any] ?? []).compactMap { raw in
        guard let map = raw as? [String: Any],
              let pattern = map["url"] as? String,
              map["matching"] as? String == "regex"
        else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }
}

private func parseTriggerFlag(_ flag: Any?) -> PostHogTriggerFlag? {
    if let flag = flag as? String {
        return PostHogTriggerFlag(flag: flag, variant: nil)
    }
    if let map = flag as? [String: Any], let flag = map["flag"] as? String {
        return PostHogTriggerFlag(flag: flag, variant: map["variant"] as? String)
    }
    return nil
}

func parseTriggerPropertyFilters(_ filters: Any?) -> [PostHogTriggerPropertyFilter] {
    (filters as? [Any] ?? []).compactMap { (raw: Any) -> PostHogTriggerPropertyFilter? in
        guard let map = raw as? [String: Any],
              let key = map["key"] as? String
        else { return nil }
        return PostHogTriggerPropertyFilter(
            key: key,
            type: map["type"] as? String,
            filterOperator: map["operator"] as? String,
            value: map["value"] is NSNull ? nil : map["value"]
        )
    }
}
