//
//  PostHogTriggerGroupsEvaluatorTests.swift
//  PostHogTests
//
//  Created on 06.10.26.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Session recording v2 trigger groups evaluator")
struct PostHogTriggerGroupsEvaluatorTests {
    private let evaluator = PostHogTriggerGroupsEvaluator()

    private func configure(_ groups: [[String: Any]]) {
        guard let config = parseTriggerGroupsConfig(["version": 2, "triggerGroups": groups]) else {
            Issue.record("trigger groups config must parse")
            return
        }
        evaluator.onConfig(config.groups)
    }

    private func eventLeg(_ events: [String: Any]...) -> [String: Any] {
        ["events": events]
    }

    private func urlLeg(_ pattern: String) -> [String: Any] {
        ["urls": [["url": pattern, "matching": "regex"]]]
    }

    private func flagLeg(_ flag: Any) -> [String: Any] {
        ["flag": flag]
    }

    private func onEvent(sessionId: String = "session-1", event: String, properties: [String: Any]? = nil) -> Bool {
        evaluator.onEvent(sessionId: sessionId, eventName: event, eventProperties: properties, personProperties: nil)
    }

    private func screen(sessionId: String = "session-1", name: String) -> Bool {
        onEvent(sessionId: sessionId, event: "$screen", properties: ["$screen_name": name])
    }

    private func decide(sessionId: String = "session-1", flags: [String: Any]? = [:]) -> PostHogTriggerGroupsDecision {
        evaluator.evaluate(sessionId: sessionId, flags: flags, personProperties: nil)
    }

    @Test("any combines activated legs and ignores disabled legs")
    func anyCombinesLegs() {
        configure([
            group(id: "g1", conditions: [
                "matchType": "any",
                "events": [["name": "purchase"]],
                "urls": [["url": "^/checkout", "matching": "regex"]],
            ]),
        ])
        // no flag configured: only event and url legs, both pending
        var decision = decide()
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)

        #expect(screen(name: "/checkout"))
        decision = decide()
        #expect(decision.shouldRecord)
        #expect(!decision.hasPendingGroups)
        #expect(decision.matchedGroups.map(\.id) == ["g1"])
    }

    @Test("all drops disabled legs and requires every configured leg")
    func allDropsDisabledLegs() {
        configure([
            group(id: "g1", conditions: [
                "matchType": "all",
                "events": [["name": "purchase"]],
                "flag": ["flag": "replay-flag", "variant": "beta"],
            ]),
        ])

        // flag leg activated, event leg pending -> pending
        var decision = decide(flags: ["replay-flag": "beta"])
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)

        // event leg activated too -> activated
        #expect(onEvent(event: "purchase"))
        decision = decide(flags: ["replay-flag": "beta"])
        #expect(decision.shouldRecord)
    }

    @Test("all with a single configured leg follows that leg")
    func allWithSingleLegFollowsIt() {
        configure([
            group(id: "g1", conditions: ["matchType": "all", "events": [["name": "purchase"]]]),
        ])

        var decision = decide()
        #expect(decision.hasPendingGroups)
        #expect(onEvent(event: "purchase"))
        decision = decide()
        #expect(decision.shouldRecord)
    }

    @Test("a leg configured but unmatched stays pending under any")
    func unmatchedLegStaysPendingUnderAny() {
        configure([group(id: "g1", conditions: ["matchType": "any", "flag": "replay-flag"])])

        let decision = decide(flags: ["replay-flag": false])
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)
    }

    @Test("empty conditions activate immediately")
    func emptyConditionsActivateImmediately() {
        configure([
            group(id: "g1", conditions: ["properties": [["key": "region", "value": "EU"]]]),
        ])

        let decision = decide()
        #expect(decision.shouldRecord)
        #expect(!decision.hasPendingGroups)
        #expect(decision.matchedGroups.map(\.id) == ["g1"])
        #expect(decision.matchedGroups.map(\.sampled) == [true])
    }

    @Test("event leg matches per-event property filters")
    func eventLegMatchesPerEventFilters() {
        configure([
            group(id: "g1", conditions: eventLeg([
                "name": "purchase",
                "properties": [["key": "amount", "operator": "gt", "value": 100]],
            ])),
        ])

        #expect(!onEvent(event: "purchase", properties: ["amount": 50]))
        #expect(!onEvent(event: "purchase", properties: ["amount": "free"]))
        #expect(decide().hasPendingGroups)
        #expect(onEvent(event: "purchase", properties: ["amount": 150]))
        #expect(decide().shouldRecord)
    }

    @Test("event leg applies exact icontains regex and is_not filters")
    func eventLegAppliesFilterOperators() throws {
        let cases: [([[String: Any]], [String: Any])] = [
            // exact
            ([["key": "plan", "value": "pro"]], ["plan": "pro"]),
            // icontains
            ([["key": "email", "operator": "icontains", "value": "@corp"]], ["email": "a@CORP.io"]),
            // regex
            ([["key": "page", "operator": "regex", "value": "^/checkout"]], ["page": "/checkout/step-2"]),
            // is_not on a missing property
            ([["key": "tier", "operator": "is_not", "value": "enterprise"]], ["unrelated": 1]),
        ]
        for (filters, properties) in cases {
            let evaluator = PostHogTriggerGroupsEvaluator()
            let config = try #require(parseTriggerGroupsConfig([
                "version": 2,
                "triggerGroups": [
                    group(id: "g1", conditions: eventLeg(["name": "purchase", "properties": filters])),
                ],
            ]))
            evaluator.onConfig(config.groups)
            #expect(
                evaluator.onEvent(sessionId: "session-1", eventName: "purchase", eventProperties: properties, personProperties: nil),
                "filters \(filters) must match \(properties)"
            )
        }
    }

    @Test("same-name event entries are a disjunction")
    func sameNameEntriesAreDisjunction() {
        configure([
            group(id: "g1", conditions: eventLeg(
                ["name": "purchase", "properties": [["key": "amount", "operator": "gt", "value": 100]]],
                ["name": "purchase", "properties": [["key": "vip", "value": true]]]
            )),
        ])

        #expect(!onEvent(event: "purchase", properties: ["amount": 50]))
        #expect(onEvent(event: "purchase", properties: ["amount": 50, "vip": true]))
    }

    @Test("group-level property filters gate the event leg")
    func groupLevelFiltersGateEventLeg() {
        configure([
            group(id: "g1", conditions: [
                "events": [["name": "purchase"]],
                "properties": [["key": "region", "value": "EU"]],
            ]),
        ])

        #expect(!onEvent(event: "purchase", properties: ["region": "US"]))
        #expect(onEvent(event: "purchase", properties: ["region": "EU"]))
    }

    @Test("group-level property filters gate the screen leg")
    func groupLevelFiltersGateScreenLeg() {
        configure([
            group(id: "g1", conditions: [
                "urls": [["url": "checkout", "matching": "regex"]],
                "properties": [["key": "region", "value": "EU"]],
            ]),
        ])

        #expect(!onEvent(event: "$screen", properties: ["$screen_name": "/checkout", "region": "US"]))
        #expect(onEvent(event: "$screen", properties: ["$screen_name": "/checkout", "region": "EU"]))
    }

    @Test("screen names match url regexes anywhere")
    func screenNamesMatchUrlRegexesAnywhere() {
        configure([group(id: "g1", conditions: urlLeg("checkout"))])

        #expect(!screen(name: "/home"))
        #expect(decide().hasPendingGroups)
        #expect(screen(name: "/en/checkout/step-2"))
        #expect(decide().shouldRecord)
    }

    @Test("a non screen event never activates the url leg")
    func nonScreenEventNeverActivatesUrlLeg() {
        configure([group(id: "g1", conditions: urlLeg("checkout"))])

        #expect(!onEvent(event: "checkout", properties: ["$screen_name": "/checkout"]))
        #expect(!decide().shouldRecord)
    }

    @Test("flag leg matches boolean flags and variants")
    func flagLegMatchesBooleanFlags() {
        configure([group(id: "g1", conditions: flagLeg("replay-flag"))])

        #expect(!decide(flags: nil).shouldRecord)
        #expect(decide(flags: nil).hasPendingGroups)
        #expect(!decide(flags: ["replay-flag": false]).shouldRecord)
        #expect(!decide(flags: ["other-flag": true]).shouldRecord)
        #expect(decide(flags: ["replay-flag": true]).shouldRecord)
    }

    @Test("flag leg with variant matches the variant or a boolean true")
    func flagLegWithVariantMatchesVariantOrTrue() {
        configure([group(id: "g1", conditions: flagLeg(["flag": "replay-flag", "variant": "beta"]))])

        #expect(!decide(flags: ["replay-flag": "alpha"]).shouldRecord)
        #expect(decide(flags: ["replay-flag": "beta"]).shouldRecord)
        // a boolean true satisfies a variant flag, matching web LinkedFlagMatching
        #expect(decide(flags: ["replay-flag": true]).shouldRecord)
    }

    @Test("flag leg without variant matches any non-empty variant")
    func flagLegWithoutVariantMatchesAnyVariant() {
        configure([group(id: "g1", conditions: flagLeg("replay-flag"))])

        #expect(decide(flags: ["replay-flag": "beta"]).shouldRecord)
        #expect(!decide(flags: ["replay-flag": ""]).shouldRecord)
    }

    @Test("activation is sticky within a session and resets on a new session")
    func activationIsStickyAndResetsPerSession() {
        configure([group(id: "g1", conditions: eventLeg(["name": "purchase"]))])

        #expect(onEvent(event: "purchase"))
        // a later non-matching event does not deactivate (and activates nothing new)
        #expect(!onEvent(event: "other"))
        #expect(decide().shouldRecord)

        var decision = decide(sessionId: "session-2")
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)
        // the previous session's activation must not leak into the new one
        #expect(!onEvent(sessionId: "session-2", event: "other"))
        decision = decide(sessionId: "session-2")
        #expect(!decision.shouldRecord)
        #expect(onEvent(sessionId: "session-2", event: "purchase"))
        #expect(decide(sessionId: "session-2").shouldRecord)
    }

    @Test("sampling decision is deterministic per session and group")
    func samplingDecisionIsDeterministic() {
        // java "session-1g-empty".hashCode() -> bucket 23; "session-2g-empty" -> bucket 12
        configure([group(id: "g-empty", sampleRate: 0.2)])
        #expect(!decide().shouldRecord)
        // same session: the stored decision is reused
        #expect(!decide().shouldRecord)

        // a new session re-decides
        #expect(decide(sessionId: "session-2").shouldRecord)
    }

    @Test("a sample rate change re-decides the same session")
    func sampleRateChangeReDecides() {
        configure([group(id: "group-1", sampleRate: 0.61)])
        #expect(!decide().shouldRecord)

        configure([group(id: "group-1", sampleRate: 0.62)])
        #expect(decide().shouldRecord)
    }

    @Test("a missing sample rate is fully sampled")
    func missingSampleRateIsFullySampled() {
        configure([group(id: "group-1", sampleRate: nil)])
        let decision = decide()
        #expect(decision.shouldRecord)
        #expect(decision.matchedGroups.map(\.sampled) == [true])
    }

    @Test("union records when any activated group is sampled in")
    func unionRecordsWhenAnyGroupSampledIn() {
        configure([
            group(id: "group-a", sampleRate: 0.0),
            group(id: "group-b", sampleRate: 1.0),
        ])

        let decision = decide()
        #expect(decision.shouldRecord)
        #expect(decision.matchedGroups.map(\.id) == ["group-a", "group-b"])
        #expect(decision.matchedGroups.map(\.sampled) == [false, true])
    }

    @Test("union keeps waiting while any group is pending")
    func unionKeepsWaitingWhilePending() {
        configure([
            group(id: "group-a", sampleRate: 0.0),
            group(id: "group-b", conditions: eventLeg(["name": "purchase"])),
        ])

        var decision = decide()
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)

        #expect(onEvent(event: "purchase"))
        decision = decide()
        // group-b activated with rate 1.0, so the union records and stops waiting
        #expect(decision.shouldRecord)
        #expect(!decision.hasPendingGroups)
    }

    @Test("union stops waiting once every group resolved")
    func unionStopsWaitingOnceResolved() {
        configure([
            group(id: "group-a", sampleRate: 0.0),
            group(id: "group-b", sampleRate: 0.0),
        ])

        let decision = decide()
        #expect(!decision.shouldRecord)
        #expect(!decision.hasPendingGroups)
    }

    @Test("minimum duration is the lowest among activated groups")
    func minimumDurationIsLowestAmongActivated() {
        configure([
            group(id: "group-a", minDurationMs: 5000),
            group(id: "group-b", minDurationMs: 1000, conditions: eventLeg(["name": "purchase"])),
        ])

        var decision = decide()
        #expect(decision.minDurationMs == 5000)

        #expect(onEvent(event: "purchase"))
        decision = decide()
        #expect(decision.minDurationMs == 1000)
    }

    @Test("minimum duration is nil without an activated group setting one")
    func minimumDurationNilWithoutActivatedGroup() {
        configure([
            group(id: "group-a", conditions: eventLeg(["name": "purchase"])),
            group(id: "group-b", minDurationMs: 1000, conditions: eventLeg(["name": "purchase"])),
        ])

        let decision = decide()
        #expect(decision.minDurationMs == nil)
    }

    @Test("a config push keeps sampling decisions for surviving groups")
    func configPushKeepsSurvivingDecisions() {
        configure([
            group(id: "group-1", sampleRate: 0.61),
            group(id: "group-2", sampleRate: 0.61),
        ])
        #expect(!decide().shouldRecord)

        // group-1 flips its rate (bucket 61 -> sampled at 0.62); group-2 keeps its stored
        // decision because neither its session nor its rate changed
        configure([
            group(id: "group-1", sampleRate: 0.62),
            group(id: "group-2", sampleRate: 0.61),
        ])
        #expect(decide().shouldRecord)
    }

    @Test("unreliable event legs are disabled so they neither record nor wait")
    func unreliableEventLegsAreDisabled() {
        // React Native captures events in JS, so the event/screen legs can never fire natively:
        // this group has no other leg, so it resolves to disabled instead of pending forever.
        configure([group(id: "g1", conditions: eventLeg(["name": "purchase"]))])

        var decision = evaluator.evaluate(sessionId: "session-1", flags: ["replay-flag": false], personProperties: nil, eventLegsReliable: false)
        #expect(!decision.shouldRecord)
        #expect(!decision.hasPendingGroups)

        // flag legs still decide under unreliable event legs
        configure([group(id: "g2", conditions: ["matchType": "any", "flag": "replay-flag"])])
        decision = evaluator.evaluate(sessionId: "session-1", flags: ["replay-flag": true], personProperties: nil, eventLegsReliable: false)
        #expect(decision.shouldRecord)
    }
}
