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
        evaluator.evaluate(sessionId: sessionId, flags: flags)
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

    @Test("group-level property filters gate the screen leg on person properties only")
    func groupLevelFiltersGateScreenLeg() {
        configure([
            group(id: "g1", conditions: [
                "urls": [["url": "checkout", "matching": "regex"]],
                "properties": [["key": "region", "value": "EU"]],
            ]),
        ])

        #expect(!onEvent(event: "$screen", properties: ["$screen_name": "/checkout", "region": "EU"]))

        configure([
            group(id: "g1", conditions: [
                "urls": [["url": "checkout", "matching": "regex"]],
                "properties": [["type": "person", "key": "plan", "value": "pro"]],
            ]),
        ])

        #expect(!evaluator.onEvent(sessionId: "session-1", eventName: "$screen",
                                   eventProperties: ["$screen_name": "/checkout"], personProperties: ["plan": "free"]))
        #expect(evaluator.onEvent(sessionId: "session-1", eventName: "$screen",
                                  eventProperties: ["$screen_name": "/checkout"], personProperties: ["plan": "pro"]))
    }

    @Test("a negative group-level event filter matches the screen leg whatever the event carries")
    func negativeGroupLevelEventFilterMatchesScreenLeg() {
        configure([
            group(id: "g1", conditions: [
                "urls": [["url": "checkout", "matching": "regex"]],
                "properties": [["key": "region", "operator": "is_not", "value": "US"]],
            ]),
        ])

        #expect(onEvent(event: "$screen", properties: ["$screen_name": "/checkout", "region": "US"]))
    }

    @Test("pending conditions name each pending leg of each pending group")
    func pendingConditionsNameEachPendingLeg() {
        configure([
            group(id: "g1", name: "Checkout", conditions: [
                "events": [["name": "purchase"]],
                "urls": [["url": "checkout", "matching": "regex"]],
                "flag": "replay-flag",
            ]),
            group(id: "g2", name: "No conditions"),
        ])

        // g2 activates at once, so only g1 is listed
        #expect(decide(flags: [:]).pendingConditions == [
            "trigger group \"Checkout\": URL condition not matched",
            "trigger group \"Checkout\": event condition not matched",
            "trigger group \"Checkout\": linked flag condition not matched",
        ])

        _ = onEvent(event: "purchase")
        #expect(decide(flags: ["replay-flag": true]).pendingConditions == [
            "trigger group \"Checkout\": URL condition not matched",
        ])

        _ = screen(name: "/checkout")
        #expect(decide(flags: ["replay-flag": true]).pendingConditions.isEmpty)
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

    @Test("an unparseable condition keeps the group pending instead of recording every session")
    func unparseableConditionStaysPending() {
        configure([group(id: "g1", conditions: ["urls": [["url": "([invalid", "matching": "regex"]]])])
        var decision = decide()
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)

        // under all, the broken leg still has to match, so the event alone does not record
        var conditions = eventLeg(["name": "purchase"])
        conditions["urls"] = [["url": "/checkout", "matching": "exact"]]
        configure([group(id: "g2", conditions: conditions)])
        #expect(onEvent(event: "purchase"))
        decision = decide()
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)
    }

    @Test("evaluating a stale session does not wipe the current session's activation")
    func staleSessionEvaluationKeepsActivation() {
        configure([group(id: "g1", conditions: eventLeg(["name": "purchase"]))])
        #expect(onEvent(sessionId: "session-2", event: "purchase"))

        #expect(!decide(sessionId: "session-1").shouldRecord)
        #expect(decide(sessionId: "session-2").shouldRecord)
    }

    private func urlOnlyCheckoutGroup(properties: [[String: Any]]? = nil) -> [String: Any] {
        var conditions = urlLeg("checkout")
        if let properties {
            conditions["properties"] = properties
        }
        return group(id: "g1", conditions: conditions)
    }

    private func sessionChanged(to sessionId: String, personProperties: [String: Any?]? = nil) -> Bool {
        evaluator.onSessionChanged(sessionId: sessionId, personProperties: personProperties)
    }

    @Test("a session change re-checks the screen the app is already on")
    func sessionChangeRechecksCurrentScreen() {
        configure([urlOnlyCheckoutGroup()])
        #expect(screen(sessionId: "session-A", name: "/checkout"))

        #expect(!decide(sessionId: "session-B").shouldRecord)
        #expect(sessionChanged(to: "session-B"))
        #expect(decide(sessionId: "session-B").shouldRecord)
    }

    @Test("a session change on a non-matching screen keeps the group pending")
    func sessionChangeOnNonMatchingScreenStaysPending() {
        configure([urlOnlyCheckoutGroup()])
        #expect(!screen(sessionId: "session-A", name: "/home"))

        #expect(!sessionChanged(to: "session-B"))
        let decision = decide(sessionId: "session-B")
        #expect(!decision.shouldRecord)
        #expect(decision.hasPendingGroups)
    }

    @Test("the remembered screen survives a reset")
    func rememberedScreenSurvivesReset() {
        configure([urlOnlyCheckoutGroup()])
        #expect(screen(sessionId: "session-A", name: "/checkout"))

        evaluator.reset()

        #expect(sessionChanged(to: "session-B"))
        #expect(decide(sessionId: "session-B").shouldRecord)
    }

    @Test("a session change to the active session leaves its activation alone")
    func sessionChangeToActiveSessionDoesNothing() {
        configure([group(id: "g1", conditions: eventLeg(["name": "purchase"]))])
        #expect(onEvent(sessionId: "session-A", event: "purchase"))

        #expect(!sessionChanged(to: "session-A"))
        #expect(decide(sessionId: "session-A").shouldRecord)
    }

    @Test("a session change with no screen seen activates nothing")
    func sessionChangeWithoutScreenActivatesNothing() {
        configure([urlOnlyCheckoutGroup()])

        #expect(!sessionChanged(to: "session-B"))
        #expect(!decide(sessionId: "session-B").shouldRecord)
    }

    @Test("a session change applies group-level person property filters to the remembered screen")
    func sessionChangeAppliesPersonPropertyFilters() {
        configure([urlOnlyCheckoutGroup(properties: [["type": "person", "key": "plan", "value": "pro"]])])
        #expect(!evaluator.onEvent(sessionId: "session-A", eventName: "$screen",
                                   eventProperties: ["$screen_name": "/checkout"], personProperties: ["plan": "free"]))

        #expect(!sessionChanged(to: "session-B", personProperties: ["plan": "free"]))
        #expect(!decide(sessionId: "session-B").shouldRecord)

        #expect(sessionChanged(to: "session-C", personProperties: ["plan": "pro"]))
        #expect(decide(sessionId: "session-C").shouldRecord)
    }

    @Test("a screen remembered before any group loads is checked at the next session change")
    func rememberedScreenSurvivesBeforeGroupsLoad() {
        evaluator.rememberScreen("/checkout")
        configure([urlOnlyCheckoutGroup()])

        #expect(sessionChanged(to: "session-B"))
        #expect(decide(sessionId: "session-B").shouldRecord)
    }

    @Test("a screen remembered while a rotating event is built keeps the old screen from activating the new session")
    func rememberedScreenBeforeRotationChecksTheNewScreen() {
        configure([urlOnlyCheckoutGroup()])
        #expect(screen(sessionId: "session-A", name: "/checkout"))

        evaluator.rememberScreen("/home")

        #expect(!sessionChanged(to: "session-B"))
        #expect(!decide(sessionId: "session-B").shouldRecord)
        #expect(decide(sessionId: "session-B").hasPendingGroups)

        #expect(!screen(sessionId: "session-B", name: "/home"))
        #expect(!decide(sessionId: "session-B").shouldRecord)
    }

    @Test("a session change checked late uses the latest remembered screen once")
    func lateSessionChangeUsesLatestScreen() {
        configure([urlOnlyCheckoutGroup()])
        #expect(!screen(sessionId: "session-A", name: "/home"))

        evaluator.rememberScreen("/checkout")

        #expect(sessionChanged(to: "session-B"))
        #expect(!sessionChanged(to: "session-B"))
    }

    private func startChecked(_ sessionId: String, personProperties: [String: Any?]? = nil) -> Bool {
        evaluator.onSessionChanged(sessionId: sessionId, personProperties: personProperties, includeCurrentSession: true)
    }

    @Test("a start checks a screen remembered in a session that already evaluated events")
    func startChecksUncheckedScreenInEvaluatedSession() {
        configure([urlOnlyCheckoutGroup()])
        #expect(!onEvent(sessionId: "session-A", event: "app_opened"))

        evaluator.rememberScreen("/checkout")

        #expect(!sessionChanged(to: "session-A"))
        #expect(startChecked("session-A"))
        #expect(decide(sessionId: "session-A").shouldRecord)
    }

    @Test("a start checks each remembered screen once per session")
    func startChecksEachScreenOnce() {
        configure([urlOnlyCheckoutGroup(properties: [["type": "person", "key": "plan", "value": "pro"]])])
        #expect(!onEvent(sessionId: "session-A", event: "app_opened"))
        evaluator.rememberScreen("/checkout")

        #expect(!startChecked("session-A", personProperties: ["plan": "free"]))
        #expect(!startChecked("session-A", personProperties: ["plan": "pro"]))

        evaluator.rememberScreen("/checkout")
        #expect(startChecked("session-A", personProperties: ["plan": "pro"]))
    }

    @Test("a screen evaluated live is not checked again in its session after a reset")
    func liveScreenNotRecheckedAfterReset() {
        configure([urlOnlyCheckoutGroup(properties: [["type": "person", "key": "plan", "value": "pro"]])])
        #expect(!evaluator.onEvent(sessionId: "session-A", eventName: "$screen",
                                   eventProperties: ["$screen_name": "/checkout"], personProperties: ["plan": "free"]))

        evaluator.reset()

        #expect(!startChecked("session-A", personProperties: ["plan": "pro"]))
        #expect(!decide(sessionId: "session-A").shouldRecord)
    }

    @Test("loaded groups are checked against a screen the previous groups were checked against")
    func loadedGroupsCheckAlreadyCheckedScreen() {
        configure([group(id: "g0", conditions: eventLeg(["name": "purchase"]))])
        #expect(!screen(sessionId: "session-A", name: "/checkout"))

        configure([urlOnlyCheckoutGroup()])

        #expect(!startChecked("session-A"))
        #expect(evaluator.recheckScreen(sessionId: "session-A", personProperties: nil))
        #expect(decide(sessionId: "session-A").shouldRecord)
    }

    @Test("a screen left unchecked by a load is checked at the next start")
    func screenMarkedUncheckedIsCheckedAtStart() {
        configure([group(id: "g0", conditions: eventLeg(["name": "purchase"]))])
        #expect(!screen(sessionId: "session-A", name: "/checkout"))

        configure([urlOnlyCheckoutGroup()])
        evaluator.markScreenUnchecked()

        #expect(startChecked("session-A"))
        #expect(decide(sessionId: "session-A").shouldRecord)
    }
}
