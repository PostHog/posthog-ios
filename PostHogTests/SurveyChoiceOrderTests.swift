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
