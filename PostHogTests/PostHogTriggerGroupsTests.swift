//
//  PostHogTriggerGroupsTests.swift
//  PostHogTests
//
//  Created on 06.10.26.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Session recording v2 trigger groups parsing")
struct PostHogTriggerGroupsTests {
    @Test("version missing or 1 keeps the v1 config")
    func versionMissingOrOneKeepsV1() {
        #expect(parseTriggerGroupsConfig(["sampleRate": 0.5, "eventTriggers": ["purchase"]]) == nil)
        #expect(parseTriggerGroupsConfig(["version": 1, "triggerGroups": [group()]]) == nil)
    }

    @Test("version 2 without usable groups keeps the v1 config")
    func versionTwoWithoutUsableGroupsKeepsV1() {
        #expect(parseTriggerGroupsConfig(["version": 2]) == nil)
        #expect(parseTriggerGroupsConfig(["version": 2, "triggerGroups": [Any]()]) == nil)
        // a group without an id cannot be identified, so it is dropped and v1 stays in effect
        #expect(parseTriggerGroupsConfig(["version": 2, "triggerGroups": [["name": "no id"]]]) == nil)
    }

    @Test("parses group sampling fields and conditions")
    func parsesGroupFields() throws {
        let config = try requireConfig(group(
            id: "group-1",
            name: "Checkout",
            sampleRate: 0.42,
            minDurationMs: 5000,
            conditions: [
                "matchType": "any",
                "events": [["name": "purchase"]],
                "urls": [["url": "^/checkout", "matching": "regex"]],
                "flag": ["flag": "replay-flag", "variant": "beta"],
                "properties": [["key": "region", "value": "EU"]],
            ] as [String: Any]
        ))

        let group = try #require(config.groups.single())
        #expect(group.id == "group-1")
        #expect(group.name == "Checkout")
        #expect(group.sampleRate == 0.42)
        #expect(group.minDurationMs == 5000)
        #expect(group.conditions.matchType == .any)
        #expect(group.conditions.events.map(\.name) == ["purchase"])
        #expect(group.conditions.events.allSatisfy { $0.properties.isEmpty })
        #expect(group.conditions.urls.map(\.pattern) == ["^/checkout"])
        #expect(group.conditions.flag?.flag == "replay-flag")
        #expect(group.conditions.flag?.variant == "beta")
        #expect(group.conditions.properties.map(\.key) == ["region"])
        #expect(group.conditions.properties.first?.value as? String == "EU")
    }

    @Test("matchType defaults to all")
    func matchTypeDefaultsToAll() throws {
        let config = try requireConfig(group(conditions: ["events": [["name": "purchase"]]]))
        #expect(try #require(config.groups.single()).conditions.matchType == .all)
    }

    @Test("events parse with per-event property filters and drop nameless entries")
    func eventsParseWithPropertyFilters() throws {
        let config = try requireConfig(group(
            conditions: [
                "events": [
                    [
                        "name": "purchase",
                        "properties": [
                            // remote-config numbers arrive as NSNumber (JSONSerialization)
                            ["key": "amount", "operator": "gt", "value": 100.0],
                        ],
                    ] as [String: Any],
                    ["properties": [["key": "orphan"]]],
                ],
            ]
        ))

        let events = try #require(config.groups.single()).conditions.events
        #expect(events.count == 1)
        #expect(events[0].properties.count == 1)
        #expect(events[0].properties[0].key == "amount")
        #expect(events[0].properties[0].filterOperator == "gt")
        #expect(events[0].properties[0].value as? Double == 100.0)
    }

    @Test("urls keep only valid regex entries")
    func urlsKeepOnlyValidRegexes() throws {
        let config = try requireConfig(group(
            conditions: [
                "urls": [
                    ["url": "^/checkout", "matching": "regex"],
                    ["url": "exact-but-unsupported", "matching": "icontains"],
                    ["url": "([invalid", "matching": "regex"],
                    ["matching": "regex"],
                ],
            ]
        ))

        let urls = try #require(config.groups.single()).conditions.urls
        #expect(urls.map { $0.pattern } == ["^/checkout"])
        #expect(matchingScreen(urls[0], "/checkout/step-2"))
        #expect(!matchingScreen(urls[0], "/home"))
    }

    @Test("flag accepts a bare string or a flag and variant map")
    func flagAcceptsStringOrMap() throws {
        let bare = try requireConfig(group(conditions: ["flag": "replay-flag"]))
        #expect(try #require(bare.groups.single()).conditions.flag?.variant == nil)

        let withVariant = try requireConfig(group(
            conditions: ["flag": ["flag": "replay-flag", "variant": "beta"]]
        ))
        #expect(try #require(withVariant.groups.single()).conditions.flag?.variant == "beta")

        let noFlagName = try requireConfig(group(conditions: ["flag": ["variant": "beta"]]))
        #expect(try #require(noFlagName.groups.single()).conditions.flag == nil)
    }

    @Test("a missing or non-number sample rate parses to nil")
    func missingOrInvalidSampleRateParsesToNil() throws {
        let config = try requireConfig([group(id: "g1", sampleRate: nil), group(id: "g2", sampleRate: "0.5")])
        #expect(try #require(config.groups.first).sampleRate == nil)
        #expect(try #require(config.groups.last).sampleRate == nil)
    }

    @Test("simple hash matches the web helper")
    func simpleHashMatchesWebHelper() {
        // java "abc".hashCode() == 96354
        #expect(simpleTriggerHash("abc") == 96_354)
        // java "posthog".hashCode() == -391202912; js Math.abs of the int32 yields 391202912
        #expect(simpleTriggerHash("posthog") == 391_202_912)
    }

    @Test("sampling uses the hash bucket like the web helper")
    func samplingUsesHashBucket() {
        // java "session-1group-1".hashCode() == 365459561; 365459561 % 100 == 61
        #expect(!sampleOnTriggerProperty("session-1group-1", 0.61))
        #expect(sampleOnTriggerProperty("session-1group-1", 0.62))
        #expect(sampleOnTriggerProperty("session-1group-1", 1.0))
        #expect(!sampleOnTriggerProperty("session-1group-1", 0.0))
    }
}

private func requireConfig(_ groups: [[String: Any]]) throws -> PostHogTriggerGroupsConfig {
    try #require(parseTriggerGroupsConfig(["version": 2, "triggerGroups": groups]))
}

private func requireConfig(_ group: [String: Any]) throws -> PostHogTriggerGroupsConfig {
    try requireConfig([group])
}

extension Sequence {
    func single() -> Element? {
        var iterator = makeIterator()
        guard let first = iterator.next(), iterator.next() == nil else { return nil }
        return first
    }
}

func matchingScreen(_ regex: NSRegularExpression, _ screenName: String) -> Bool {
    regex.firstMatch(in: screenName, range: NSRange(screenName.startIndex..., in: screenName)) != nil
}

func group(id: String = "g1",
           name: String = "Group 1",
           sampleRate: Any? = 1.0,
           minDurationMs: Any? = nil,
           conditions: [String: Any] = [:]) -> [String: Any] {
    [
        "id": id,
        "name": name,
        "sampleRate": sampleRate as Any,
        "minDurationMs": minDurationMs as Any,
        "conditions": conditions,
    ]
}
