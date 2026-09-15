import Foundation
@testable import PostHog
import Testing

@Suite("Survey choice display order")
struct SurveyChoiceOrderTests {
    @Test("Disabled shuffling preserves configured order", arguments: [false, true])
    func disabled(hasOpenChoice: Bool) {
        #expect(surveyChoiceOrder(options: ["A", "B", "Other"], hasOpenChoice: hasOpenChoice, shuffleOptions: false) == [0, 1, 2])
    }

    @Test("Shuffling preserves identities and pins the open choice", arguments: [false, true])
    func shuffled(hasOpenChoice: Bool) {
        let choices = ["A", "B", "C", "Other"]
        let order = surveyChoiceOrder(options: choices, hasOpenChoice: hasOpenChoice, shuffleOptions: true)
        #expect(order.sorted() == Array(choices.indices))
        #expect(order != Array(choices.indices))
        if hasOpenChoice { #expect(order.last == choices.count - 1) }
    }

    @Test("Two regular choices always swap, matching web's unchanged-order fallback", arguments: [false, true])
    func twoChoices(hasOpenChoice: Bool) {
        let choices = hasOpenChoice ? ["A", "B", "Other"] : ["A", "B"]
        #expect(surveyChoiceOrder(options: choices, hasOpenChoice: hasOpenChoice, shuffleOptions: true) == (hasOpenChoice ? [1, 0, 2] : [1, 0]))
    }

    @Test("Small and duplicate choice lists retain every original index", arguments: [[], ["Other"], ["A", "Other"], ["A", "A", "Other"]], [false, true])
    func edgeCases(choices: [String], hasOpenChoice: Bool) {
        let order = surveyChoiceOrder(options: choices, hasOpenChoice: hasOpenChoice, shuffleOptions: true)
        #expect(order.sorted() == Array(choices.indices))
        if hasOpenChoice, !choices.isEmpty { #expect(order.last == choices.count - 1) }
    }
}

@Suite("Survey choice order updates")
struct SurveyChoiceOrderUpdateTests {
    @Test("Choice-count changes preserve surviving order and keep Other last", arguments: [
        ([2, 0, 1, 3], 5, true, [2, 0, 1, 3, 4]),
        ([2, 0, 1, 3], 3, true, [0, 1, 2]),
        ([2, 0, 1], 4, false, [2, 0, 1, 3]),
        ([2, 0, 1], 2, false, [0, 1]),
        ([2, 0, 1, 3], 4, true, [2, 0, 1, 3]),
        ([0], 0, true, []),
        ([], 1, true, [0]),
    ] as [([Int], Int, Bool, [Int])])
    func update(order: [Int], count: Int, hasOpenChoice: Bool, expected: [Int]) {
        #expect(updatedSurveyChoiceOrder(order, optionCount: count, hasOpenChoice: hasOpenChoice) == expected)
    }

    @Test("Choice-count changes retain selections by identity, including Other", arguments: [
        (Set([1, 3]), 4, 5, true, Set([1, 4])),
        (Set([1, 2, 3]), 4, 3, true, Set([1, 2])),
        (Set([1, 2]), 3, 2, false, Set([1])),
        (Set([0]), 1, 0, true, Set<Int>()),
    ])
    func selection(selected: Set<Int>, oldCount: Int, count: Int, hasOpenChoice: Bool, expected: Set<Int>) {
        #expect(updatedSurveyChoiceSelection(selected, previousCount: oldCount, optionCount: count, hasOpenChoice: hasOpenChoice) == expected)
    }
}
