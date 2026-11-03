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

/// A leg counts as configured when the raw config has it, even if none of its entries parse: like
/// posthog-js, an unparseable condition then never matches instead of dropping out and letting the
/// group record every session.
struct PostHogTriggerConditions {
    let matchType: PostHogTriggerMatchType
    let events: [PostHogTriggerEvent]
    let urls: [NSRegularExpression]
    let flag: PostHogTriggerFlag?
    let properties: [PostHogTriggerPropertyFilter]
    let hasEventsLeg: Bool
    let hasUrlsLeg: Bool
    let hasFlagLeg: Bool
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
            sampleRate: parseTriggerGroupSampleRate(map["sampleRate"]),
            minDurationMs: (map["minDurationMs"] as? NSNumber)?.int64Value,
            conditions: parseTriggerConditions(map["conditions"])
        )
    }

    if groups.isEmpty { return nil }

    return PostHogTriggerGroupsConfig(groups: groups)
}

/// The API can send the rate as a string. One that doesn't parse samples out, as it does on web
/// (NaN never passes the threshold); only a missing rate samples in.
private func parseTriggerGroupSampleRate(_ raw: Any?) -> Double? {
    if let string = raw as? String {
        return Double(string) ?? 0
    }
    return (raw as? NSNumber)?.doubleValue
}

private func parseTriggerConditions(_ conditions: Any?) -> PostHogTriggerConditions {
    let map = conditions as? [String: Any]
    let rawFlag = map?["flag"]
    return PostHogTriggerConditions(
        matchType: map?["matchType"] as? String == "any" ? .any : .all,
        events: parseTriggerEvents(map?["events"]),
        urls: parseTriggerUrls(map?["urls"]),
        flag: parseTriggerFlag(rawFlag),
        properties: parseTriggerPropertyFilters(map?["properties"]),
        hasEventsLeg: !(map?["events"] as? [Any] ?? []).isEmpty,
        hasUrlsLeg: !(map?["urls"] as? [Any] ?? []).isEmpty,
        hasFlagLeg: !(rawFlag as? String ?? "").isEmpty || rawFlag is [String: Any]
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
