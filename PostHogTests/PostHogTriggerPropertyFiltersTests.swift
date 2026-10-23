//
//  PostHogTriggerPropertyFiltersTests.swift
//  PostHogTests
//
//  Created on 06.10.26.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Session recording v2 trigger property filters")
struct PostHogTriggerPropertyFiltersTests {
    @Test("empty or missing filter list matches")
    func emptyOrMissingListMatches() {
        #expect(matchTriggerPropertyFilters(nil, ["plan": "free"], nil))
        #expect(matchTriggerPropertyFilters([], nil, nil))
    }

    @Test("exact matches case sensitively")
    func exactMatchesCaseSensitively() {
        #expect(match(filter: filter(), event: ["plan": "pro"]))
        #expect(!match(filter: filter(), event: ["plan": "PRO"]))
        #expect(!match(filter: filter(), event: ["plan": "free"]))
    }

    @Test("exact compares numbers with js string semantics")
    func exactComparesNumbersLikeJS() {
        // Remote-config numbers arrive as NSNumber while event properties are often Int;
        // JS String(100) === String(100.0), so the string forms must match too.
        #expect(match(filter: filter(key: "amount", value: 100.0), event: ["amount": 100]))
        #expect(match(filter: filter(key: "amount", value: 100), event: ["amount": 100.0]))
        #expect(!match(filter: filter(key: "amount", value: 100.5), event: ["amount": 100]))
    }

    @Test("exact matches any element of array values")
    func exactMatchesArrayElements() {
        #expect(match(filter: filter(value: ["free", "pro"]), event: ["plan": "pro"]))
        #expect(!match(filter: filter(value: ["free", "enterprise"]), event: ["plan": "pro"]))
    }

    @Test("booleans stringify to true and false like js String()")
    func booleansStringifyLikeJS() {
        #expect(match(filter: filter(key: "vip", value: true), event: ["vip": true]))
        #expect(!match(filter: filter(key: "vip", value: true), event: ["vip": false]))
        #expect(!match(filter: filter(key: "vip", value: "true"), event: ["vip": 1]))
    }

    @Test("is_not matches when the property is missing or null")
    func isNotMatchesMissingOrNull() {
        #expect(match(filter: filter(operator: "is_not"), event: nil))
        #expect(match(filter: filter(operator: "is_not"), event: ["other": 1]))
        #expect(match(filter: filter(operator: "is_not"), event: ["plan": NSNull()]))
        #expect(match(filter: filter(operator: "is_not"), event: ["plan": "free"]))
        #expect(!match(filter: filter(operator: "is_not"), event: ["plan": "pro"]))
    }

    @Test("positive operators do not match a missing property")
    func positiveOperatorsDoNotMatchMissing() {
        for filterOperator in [nil, "exact", "icontains", "regex", "gt", "lt"] {
            #expect(
                !match(filter: filter(operator: filterOperator), event: [:]),
                "operator \(filterOperator ?? "nil") must not match a missing property"
            )
        }
    }

    @Test("negative operators match a missing property")
    func negativeOperatorsMatchMissing() {
        for filterOperator in ["is_not", "not_icontains", "not_regex"] {
            #expect(match(filter: filter(operator: filterOperator), event: [:]))
        }
    }

    @Test("icontains is a case-insensitive substring match")
    func icontainsIsCaseInsensitiveSubstring() {
        #expect(match(filter: filter(key: "email", operator: "icontains", value: "@CORP"), event: ["email": "marc@corp.com"]))
        #expect(!match(filter: filter(key: "email", operator: "icontains", value: "@corp"), event: ["email": "marc@example.com"]))
    }

    @Test("not_icontains requires no element to contain the target")
    func notIcontainsRequiresNone() {
        #expect(match(filter: filter(key: "email", operator: "not_icontains", value: "@corp"), event: ["email": "marc@example.com"]))
        #expect(!match(filter: filter(key: "email", operator: "not_icontains", value: "@corp"), event: ["email": "a@CORP.io"]))
    }

    @Test("regex searches the property value")
    func regexSearchesValue() {
        let regexFilter = filter(key: "page", operator: "regex", value: "checkout/step-\\d+")
        #expect(match(filter: regexFilter, event: ["page": "/en/checkout/step-2"]))
        #expect(!match(filter: regexFilter, event: ["page": "/home"]))
        #expect(!match(filter: regexFilter, event: ["page": "checkout step x"]))
    }

    @Test("an invalid regex never matches and its negation always does")
    func invalidRegexNeverMatches() {
        #expect(!match(filter: filter(operator: "regex", value: "(["), event: ["plan": "pro"]))
        #expect(match(filter: filter(operator: "not_regex", value: "(["), event: ["plan": "pro"]))
    }

    @Test("gt and lt compare numerically with js parseFloat semantics")
    func gtLtCompareNumericallyLikeParseFloat() {
        let gt = filter(key: "amount", operator: "gt", value: 100)
        #expect(match(filter: gt, event: ["amount": 150]))
        #expect(!match(filter: gt, event: ["amount": 100]))
        #expect(!match(filter: gt, event: ["amount": "free"]))
        // parseFloat("10items") is 10, like on web
        #expect(!match(filter: gt, event: ["amount": "10items"]))
        #expect(match(filter: filter(key: "amount", operator: "gt", value: 9), event: ["amount": "10items"]))

        let lt = filter(key: "amount", operator: "lt", value: "50.5")
        #expect(match(filter: lt, event: ["amount": 50]))
        #expect(!match(filter: lt, event: ["amount": 50.5]))
        #expect(!match(filter: filter(key: "amount", operator: "lt", value: "40"), event: ["amount": "50items"]))
    }

    @Test("unknown operator does not match")
    func unknownOperatorDoesNotMatch() {
        #expect(!match(filter: filter(operator: "regex_ish"), event: ["plan": "pro"]))
    }

    @Test("missing filter value does not match")
    func missingFilterValueDoesNotMatch() {
        #expect(!match(filter: filter(value: nil), event: ["plan": "pro"]))
        #expect(!match(filter: filter(operator: "is_not", value: nil), event: ["plan": "pro"]))
    }

    @Test("person type reads person properties and event type reads event properties")
    func personTypeReadsPersonProperties() {
        let personFilter = filter(type: "person")
        #expect(match(filter: personFilter, event: ["plan": "free"], person: ["plan": "pro"]))
        #expect(!match(filter: personFilter, event: ["plan": "pro"], person: ["plan": "free"]))
        #expect(!match(filter: personFilter, event: ["plan": "pro"], person: nil))

        #expect(match(filter: filter(), event: ["plan": "pro"], person: ["plan": "free"]))
    }

    @Test("all filters must match")
    func allFiltersMustMatch() {
        let filters = [
            filter(key: "plan", value: "pro"),
            filter(key: "region", value: "EU"),
        ]
        #expect(matchTriggerPropertyFilters(filters, ["plan": "pro", "region": "EU"], nil))
        #expect(!matchTriggerPropertyFilters(filters, ["plan": "pro", "region": "US"], nil))
    }
}

private func filter(key: String = "plan",
                    operator: String? = nil,
                    value: Any? = "pro",
                    type: String? = nil) -> PostHogTriggerPropertyFilter {
    PostHogTriggerPropertyFilter(key: key, type: type, filterOperator: `operator`, value: value)
}

private func match(filter: PostHogTriggerPropertyFilter,
                   event: [String: Any?]?,
                   person: [String: Any?]? = nil) -> Bool {
    matchTriggerPropertyFilters([filter], event, person)
}
