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

    func onEvent(sessionId: String,
                 eventName: String,
                 eventProperties: [String: Any?]?,
                 personProperties: [String: Any?]?) -> Bool
    {
        lock.withLock {
            resetActivationForNewSessionLocked(sessionId)

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

                if eventName == Self.screenEventName {
                    let screenName = (eventProperties?[Self.screenNameProperty] ?? nil) as? String
                    let screenMatched = screenName != nil
                        && !conditions.urls.isEmpty
                        && !screenActivatedGroupIds.contains(group.id)
                        && conditions.urls.contains { regex in
                            guard let screenName else { return false }
                            return regex.firstMatch(in: screenName, range: NSRange(screenName.startIndex..., in: screenName)) != nil
                        }
                        && matchTriggerPropertyFilters(conditions.properties, eventProperties, personProperties)
                    if screenMatched {
                        screenActivatedGroupIds.insert(group.id)
                        anyNewlyActivated = true
                    }
                }
            }
            return anyNewlyActivated
        }
    }

    /// Read-only for activation: a caller holding a stale session id must not wipe the current
    /// session's activated groups. Only `onEvent` moves activation to a new session.
    func evaluate(sessionId: String, flags: [String: Any]?) -> PostHogTriggerGroupsDecision {
        lock.withLock {
            let activatedSession = activationSessionId == sessionId

            var shouldRecord = false
            var hasPendingGroups = false
            var minDurationMs: Int64?
            var matchedGroups: [PostHogTriggerGroupMatch] = []

            for group in groups {
                switch groupStatusLocked(group, flags: flags, activatedSession: activatedSession) {
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
                case .disabled:
                    break
                }
            }

            return PostHogTriggerGroupsDecision(
                shouldRecord: shouldRecord,
                hasPendingGroups: hasPendingGroups,
                minDurationMs: minDurationMs,
                groupsCount: groups.count,
                matchedGroups: matchedGroups
            )
        }
    }

    private func groupStatusLocked(_ group: PostHogTriggerGroup,
                                   flags: [String: Any]?,
                                   activatedSession: Bool) -> PostHogTriggerStatus
    {
        let conditions = group.conditions
        let hasEvents = conditions.hasEventsLeg
        let hasUrls = conditions.hasUrlsLeg
        let hasFlag = conditions.hasFlagLeg

        if !hasEvents && !hasUrls && !hasFlag { return .activated }

        let eventLeg: PostHogTriggerStatus
        if !hasEvents {
            eventLeg = .disabled
        } else if activatedSession, eventActivatedGroupIds.contains(group.id) {
            eventLeg = .activated
        } else {
            eventLeg = .pending
        }

        let screenLeg: PostHogTriggerStatus
        if !hasUrls {
            screenLeg = .disabled
        } else if activatedSession, screenActivatedGroupIds.contains(group.id) {
            screenLeg = .activated
        } else {
            screenLeg = .pending
        }

        let flagLeg = hasFlag ? Self.flagLegStatus(conditions.flag, flags: flags) : .disabled

        return conditions.matchType == .any
            ? Self.orTriggerStatus(eventLeg, screenLeg, flagLeg)
            : Self.andTriggerStatus(eventLeg, screenLeg, flagLeg)
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
