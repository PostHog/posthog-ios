import XCTest

final class SurveyAutoSubmitUITests: XCTestCase {
    private var app: XCUIApplication!
    private var continueButton: XCUIElement { app.buttons["posthog.survey.primary-action"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testNumberAutoSubmitAndConsecutiveQuestionReset() {
        assertAutoSubmit(kind: "number", answer: "4")
    }

    func testEmojiAutoSubmitAndConsecutiveQuestionReset() {
        assertAutoSubmit(kind: "emoji", answer: "4")
    }

    func testSingleChoiceAutoSubmitAndConsecutiveQuestionReset() {
        assertAutoSubmit(kind: "single", answer: "First")
    }

    func testFalseAndMissingFlagRequireExplicitSubmission() {
        for kind in ["number", "emoji", "single"] {
            for flag in ["false", "missing"] {
                launch(kind: kind, flag: flag)
                XCTAssertTrue(continueButton.exists)
                XCTAssertFalse(continueButton.isEnabled)
                select(kind: kind)
                XCTAssertTrue(app.staticTexts["First question"].exists)
                assertAnswers("")
                XCTAssertTrue(continueButton.isEnabled)
                continueButton.tap()
                assertQuestion("Second question")
                assertAnswers(kind == "single" ? "0:First" : "0:4")
                app.terminate()
            }
        }
    }

    func testOpenChoiceRequiresTextAndExplicitSubmission() {
        launch(kind: "open")
        app.buttons["First"].tap()
        assertAnswers("")
        XCTAssertTrue(continueButton.isEnabled)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Other:")).firstMatch.tap()
        XCTAssertFalse(continueButton.isEnabled)
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Custom answer")
        assertAnswers("")
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        assertQuestion("Second question")
        assertAnswers("0:Custom answer")
    }

    func testMultipleChoiceKeepsExplicitSubmission() {
        launch(kind: "multiple")
        app.buttons["First"].tap()
        app.buttons["Second"].tap()
        assertQuestion("First question")
        assertAnswers("")
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        assertQuestion("Second question")
        assertAnswers("0:First,Second")
    }

    func testOptionalQuestionCanStillSkipWithExplicitSubmission() {
        launch(kind: "number", flag: "false", optional: true)
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        assertQuestion("Second question")
        assertAnswers("0:nil")
    }

    private func assertAutoSubmit(kind: String, answer: String) {
        launch(kind: kind)
        XCTAssertFalse(continueButton.exists)
        select(kind: kind)
        assertQuestion("Second question")
        assertAnswers("0:\(answer)")
        XCTAssertTrue(continueButton.exists)
        XCTAssertFalse(continueButton.isEnabled, "The next question must start without the previous selection")
        select(kind: kind)
        XCTAssertTrue(continueButton.isEnabled)
        assertAnswers("0:\(answer)")
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Thank you for your feedback!"].waitForExistence(timeout: 5))
        assertAnswers("0:\(answer)|2:\(answer)")
    }

    private func launch(kind: String, flag: String = "true", optional: Bool = false) {
        app.launchEnvironment = [
            "SURVEY_KIND": kind, "SURVEY_SKIP": flag,
            "SURVEY_OPTIONAL": String(optional),
        ]
        app.launch()
        assertQuestion("First question")
        assertAnswers("")
    }

    private func select(kind: String) {
        if kind == "single" {
            app.buttons["First"].tap()
        } else if kind == "emoji" {
            // Emoji artwork has no text label. Locate the five actual rating buttons
            // by their control dimensions, then tap the fourth in display order.
            let ratings = app.buttons.allElementsBoundByIndex.filter {
                abs($0.frame.width - 48) < 1 && abs($0.frame.height - 48) < 1
            }.sorted { $0.frame.minX < $1.frame.minX }
            XCTAssertEqual(ratings.count, 5)
            ratings[3].tap()
        } else {
            app.buttons["4"].tap()
        }
    }

    private func assertQuestion(_ title: String) {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Skipped question"].exists)
    }

    private func assertAnswers(_ expected: String) {
        let predicate = NSPredicate(format: "label == %@", expected.isEmpty ? "none" : expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["answers"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
