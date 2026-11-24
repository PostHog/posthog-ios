//
//  PostHogTriggerGroupsEvaluator.swift
//  PostHog
//
//  Created on 06.10.26.
//

import Foundation

struct PostHogTriggerGroupMatch {
    let id: String
    let name: String
    let sampled: Bool
}

struct PostHogTriggerGroupsDecision {
    let shouldRecord: Bool
    let hasPendingGroups: Bool
    let minDurationMs: Int64?
    let groupsCount: Int
    let matchedGroups: [PostHogTriggerGroupMatch]
    /// `trigger group "<name>": <leg> condition not matched` for each pending leg of each pending group.
    let pendingConditions: [String]
}

private enum PostHogTriggerStatus {
    case activated
    case pending
    case disabled
}

class PostHogTriggerGroupsEvaluator {
    private let lock = NSLock()

    private var groups: [PostHogTriggerGroup] = []

    private var activationSessionId: String?
    private var eventActivatedGroupIds: Set<String> = []
    private var screenActivatedGroupIds: Set<String> = []
    private var lastScreenName: String?
    /// The session the groups were last checked against `lastScreenName` in; nil while no group was.
    private var screenCheckedSessionId: String?

    private var samplingDecisions: [String: StoredSamplingDecision] = [:]

    private struct StoredSamplingDecision {
        let sessionId: String
        let sampleRate: Double?
        let sampled: Bool
    }

    func onConfig(_ newGroups: [PostHogTriggerGroup]) {
        lock.withLock {
            let newIds = Set(newGroups.map(\.id))
            samplingDecisions = samplingDecisions.filter { newIds.contains($0.key) }
            groups = newGroups
        }
    }

    /// Drops the session activation while keeping the configured groups, so a post-reset session
    /// re-activates the groups from scratch. With no activation session no group reads as activated,
    /// and the next event clears the group sets as for any new session. Sampling decisions are a
    /// deterministic per-session cache (as in posthog-js), so they stay.
    func reset() {
        lock.withLock { activationSessionId = nil }
    }

    /// The screen the app is on, kept even when no event reaches `onEvent` (replay stopped, not installed,
    /// no groups loaded) so a later session change checks the right screen.
    func rememberScreen(_ screenName: String) {
        lock.withLock {
            lastScreenName = screenName
            screenCheckedSessionId = nil
        }
    }

    func onEvent(sessionId: String,
                 eventName: String,
                 eventProperties: [String: Any?]?,
                 personProperties: [String: Any?]?) -> Bool
    {
        lock.withLock {
            resetActivationForNewSessionLocked(sessionId)

            let screenName = eventName == Self.screenEventName
                ? (eventProperties?[Self.screenNameProperty] ?? nil) as? String
                : nil
            if let screenName {
                lastScreenName = screenName
                screenCheckedSessionId = sessionId
            }

            var anyNewlyActivated = false
            for group in groups {
                let conditions = group.conditions

                let eventMatched = !conditions.events.isEmpty
                    && !eventActivatedGroupIds.contains(group.id)
                    && Self.matchesEventLeg(conditions, eventName: eventName, eventProperties: eventProperties, personProperties: personProperties)
                if eventMatched {
                    eventActivatedGroupIds.insert(group.id)
                    anyNewlyActivated = true
                }

                if let screenName, matchesScreenLegLocked(group, screenName: screenName, personProperties: personProperties) {
                    screenActivatedGroupIds.insert(group.id)
                    anyNewlyActivated = true
                }
            }
            return anyNewlyActivated
        }
    }

    /// A new session starts with no activated groups, so the screen the app is already on must be
    /// re-checked: no `$screen` event follows to do it. With `includeCurrentSession`, the current session
    /// is checked too, against a screen no group was checked against in it. Each screen is checked once per session.
    func onSessionChanged(sessionId: String, personProperties: [String: Any?]?, includeCurrentSession: Bool = false) -> Bool {
        lock.withLock {
            guard activationSessionId != sessionId || includeCurrentSession else { return false }
            resetActivationForNewSessionLocked(sessionId)

            guard screenCheckedSessionId != sessionId else { return false }
            return checkScreenLocked(sessionId: sessionId, personProperties: personProperties)
        }
    }

    /// Groups that just loaded were never checked against the screen the app is on, even when the previous
    /// groups were checked against it in this session, so check it again.
    func onGroupsLoaded(sessionId: String, personProperties: [String: Any?]?) -> Bool {
        lock.withLock {
            resetActivationForNewSessionLocked(sessionId)
            return checkScreenLocked(sessionId: sessionId, personProperties: personProperties)
        }
    }

    /// Leaves the screen the app is on unchecked in the current session, so the next explicit start checks it.
    func markScreenUnchecked() {
        lock.withLock { screenCheckedSessionId = nil }
    }

    /// Read-only for activation: a caller holding a stale session id must not wipe the current
    /// session's activated groups. Only `onEvent`, `onSessionChanged` and `onGroupsLoaded` move activation to a new session.
    func evaluate(sessionId: String, flags: [String: Any]?) -> PostHogTriggerGroupsDecision {
        lock.withLock {
            let activatedSession = activationSessionId == sessionId

            var shouldRecord = false
            var hasPendingGroups = false
            var minDurationMs: Int64?
            var matchedGroups: [PostHogTriggerGroupMatch] = []
            var pendingConditions: [String] = []

            for group in groups {
                let legs = legStatusesLocked(group, flags: flags, activatedSession: activatedSession)
                switch Self.groupStatus(group, legs: legs) {
                case .activated:
                    let sampled = samplingDecisionLocked(group, sessionId: sessionId)
                    matchedGroups.append(PostHogTriggerGroupMatch(id: group.id, name: group.name, sampled: sampled))
                    if sampled {
                        shouldRecord = true
                    }
                    if let duration = group.minDurationMs {
                        minDurationMs = minDurationMs.map { min($0, duration) } ?? duration
                    }
                case .pending:
                    hasPendingGroups = true
                    pendingConditions += legs.pendingLabels.map { "trigger group \"\(group.name)\": \($0)" }
                case .disabled:
                    break
                }
            }

            return PostHogTriggerGroupsDecision(
                shouldRecord: shouldRecord,
                hasPendingGroups: hasPendingGroups,
                minDurationMs: minDurationMs,
                groupsCount: groups.count,
                matchedGroups: matchedGroups,
                pendingConditions: pendingConditions
            )
        }
    }

    private struct LegStatuses {
        let event: PostHogTriggerStatus
        let screen: PostHogTriggerStatus
        let flag: PostHogTriggerStatus

        /// The screen leg reports as the URL leg.
        var pendingLabels: [String] {
            [
                (screen, "URL condition not matched"),
                (event, "event condition not matched"),
                (flag, "linked flag condition not matched"),
            ].filter { $0.0 == .pending }.map(\.1)
        }
    }

    private func legStatusesLocked(_ group: PostHogTriggerGroup,
                                   flags: [String: Any]?,
                                   activatedSession: Bool) -> LegStatuses
    {
        let conditions = group.conditions

        let eventLeg: PostHogTriggerStatus
        if !conditions.hasEventsLeg {
            eventLeg = .disabled
        } else if activatedSession, eventActivatedGroupIds.contains(group.id) {
            eventLeg = .activated
        } else {
            eventLeg = .pending
        }

        let screenLeg: PostHogTriggerStatus
        if !conditions.hasUrlsLeg {
            screenLeg = .disabled
        } else if activatedSession, screenActivatedGroupIds.contains(group.id) {
            screenLeg = .activated
        } else {
            screenLeg = .pending
        }

        let flagLeg = conditions.hasFlagLeg ? Self.flagLegStatus(conditions.flag, flags: flags) : .disabled

        return LegStatuses(event: eventLeg, screen: screenLeg, flag: flagLeg)
    }

    private static func groupStatus(_ group: PostHogTriggerGroup, legs: LegStatuses) -> PostHogTriggerStatus {
        let conditions = group.conditions
        if !conditions.hasEventsLeg && !conditions.hasUrlsLeg && !conditions.hasFlagLeg { return .activated }

        return conditions.matchType == .any
            ? orTriggerStatus(legs.event, legs.screen, legs.flag)
            : andTriggerStatus(legs.event, legs.screen, legs.flag)
    }

    /// A configured flag leg that didn't parse never matches.
    private static func flagLegStatus(_ flag: PostHogTriggerFlag?, flags: [String: Any]?) -> PostHogTriggerStatus {
        guard let flag, let flags else { return .pending }

        let value = flags[flag.flag]
        let matches: Bool
        if let boolValue = value as? Bool {
            matches = boolValue
        } else if let variantValue = value as? String {
            if let variant = flag.variant {
                matches = variantValue == variant
            } else {
                matches = !variantValue.isEmpty
            }
        } else {
            matches = false
        }
        return matches ? .activated : .pending
    }

    private static func orTriggerStatus(_ statuses: PostHogTriggerStatus...) -> PostHogTriggerStatus {
        if statuses.contains(.activated) { return .activated }
        if statuses.contains(.pending) { return .pending }
        return .disabled
    }

    private static func andTriggerStatus(_ statuses: PostHogTriggerStatus...) -> PostHogTriggerStatus {
        let enabled = statuses.filter { $0 != .disabled }
        guard let first = enabled.first else { return .disabled }
        return enabled.allSatisfy { $0 == first } ? first : .pending
    }

    private static func matchesEventLeg(_ conditions: PostHogTriggerConditions,
                                        eventName: String,
                                        eventProperties: [String: Any?]?,
                                        personProperties: [String: Any?]?) -> Bool
    {
        let namedEntries = conditions.events.filter { $0.name == eventName }
        if namedEntries.isEmpty { return false }

        let entryMatched = namedEntries.contains { entry in
            entry.properties.isEmpty
                || matchTriggerPropertyFilters(entry.properties, eventProperties, personProperties)
        }
        if !entryMatched { return false }

        return matchTriggerPropertyFilters(conditions.properties, eventProperties, personProperties)
    }

    private func matchesScreenLegLocked(_ group: PostHogTriggerGroup,
                                        screenName: String,
                                        personProperties: [String: Any?]?) -> Bool
    {
        let conditions = group.conditions
        return !conditions.urls.isEmpty
            && !screenActivatedGroupIds.contains(group.id)
            && conditions.urls.contains { $0.firstMatch(in: screenName, range: NSRange(screenName.startIndex..., in: screenName)) != nil }
            // The screen leg checks group-level filters without event properties
            && matchTriggerPropertyFilters(conditions.properties, nil, personProperties)
    }

    private func checkScreenLocked(sessionId: String, personProperties: [String: Any?]?) -> Bool {
        guard let screenName = lastScreenName else { return false }
        screenCheckedSessionId = sessionId

        var anyNewlyActivated = false
        for group in groups where matchesScreenLegLocked(group, screenName: screenName, personProperties: personProperties) {
            screenActivatedGroupIds.insert(group.id)
            anyNewlyActivated = true
        }
        return anyNewlyActivated
    }

    private func samplingDecisionLocked(_ group: PostHogTriggerGroup, sessionId: String) -> Bool {
        if let stored = samplingDecisions[group.id],
           stored.sessionId == sessionId, stored.sampleRate == group.sampleRate
        {
            return stored.sampled
        }

        let sampled = group.sampleRate.map { sampleOnProperty(sessionId + group.id, $0) } ?? true

        samplingDecisions[group.id] = StoredSamplingDecision(sessionId: sessionId, sampleRate: group.sampleRate, sampled: sampled)
        return sampled
    }

    private func resetActivationForNewSessionLocked(_ sessionId: String) {
        if activationSessionId != sessionId {
            activationSessionId = sessionId
            eventActivatedGroupIds.removeAll()
            screenActivatedGroupIds.removeAll()
        }
    }

    private static let screenEventName = "$screen"
    private static let screenNameProperty = "$screen_name"
}
