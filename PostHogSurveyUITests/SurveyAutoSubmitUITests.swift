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

    func testPositionedCardsHonorVerticalAndHorizontalAnchors() {
        var closeFrames: [String: CGRect] = [:]
        var screenWidth: CGFloat = 0
        let rows = [
            ["top_left", "top_center", "top_right"],
            ["middle_left", "middle_center", "middle_right"],
            ["left", "center", "right"],
        ]
        for position in rows.flatMap({ $0 }) {
            launchPositionedSurvey(position: position)
            screenWidth = app.frame.width
            let close = app.buttons["posthog.survey.dismiss"]
            closeFrames[position] = close.frame
            XCTAssertTrue(close.isHittable, position)
            XCTAssertTrue(app.buttons["4"].isHittable, position)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = position
            screenshot.lifetime = .keepAlways
            add(screenshot)
            close.tap()
            let closed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "closed"),
                object: app.staticTexts["survey-status"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed, position)
            app.terminate()
        }
        for column in 0 ... 2 {
            let top = closeFrames[rows[0][column]]!
            let middle = closeFrames[rows[1][column]]!
            let bottom = closeFrames[rows[2][column]]!
            XCTAssertGreaterThan(middle.midY, top.midY + 80)
            XCTAssertGreaterThan(bottom.midY, middle.midY + 80)
        }
        if screenWidth > 600 {
            for row in rows.prefix(2) {
                XCTAssertGreaterThan(closeFrames[row[1]]!.midX, closeFrames[row[0]]!.midX + 20)
                XCTAssertGreaterThan(closeFrames[row[2]]!.midX, closeFrames[row[1]]!.midX + 20)
            }
            XCTAssertGreaterThan(closeFrames["right"]!.midX, closeFrames["left"]!.midX + 40)
        }
    }

    func testPositionedCardScrollsLongContentAndResizesAfterAnswer() {
        launchPositionedSurvey(position: "right", longContent: true)
        let close = app.buttons["posthog.survey.dismiss"]
        let longContentCloseY = close.frame.midY
        let lastChoice = app.buttons["Choice 30"]
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists)
        for _ in 0 ..< 15 {
            if lastChoice.isHittable { break }
            scrollView.swipeUp()
        }
        XCTAssertTrue(lastChoice.isHittable)
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.frame.midY, longContentCloseY, accuracy: 2)
        lastChoice.tap()
        continueButton.tap()
        assertQuestion("Second question")
        XCTAssertTrue(app.buttons["First"].isHittable)
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertGreaterThan(close.frame.midY, longContentCloseY + 80)
        close.tap()
    }

    func testPositionedCardFitsAWindowShorterThanTheScreen() {
        launchPositionedSurvey(position: "middle_right", longContent: true, windowHeight: 400)
        let window = app.windows.containing(.button, identifier: "posthog.survey.dismiss").firstMatch
        XCTAssertEqual(window.frame.height, 400, accuracy: 1)
        let close = app.buttons["posthog.survey.dismiss"]
        let scrollView = app.scrollViews.firstMatch
        XCTAssertGreaterThanOrEqual(close.frame.minY, window.frame.minY)
        XCTAssertLessThanOrEqual(scrollView.frame.maxY, window.frame.maxY)
        XCTAssertTrue(close.isHittable)
        let lastChoice = app.buttons["Choice 30"]
        for _ in 0 ..< 20 {
            if lastChoice.isHittable { break }
            scrollView.swipeUp()
        }
        XCTAssertTrue(lastChoice.isHittable)
        lastChoice.tap()
        continueButton.tap()
        assertQuestion("Second question")
        XCTAssertTrue(app.buttons["First"].isHittable)
        XCTAssertTrue(close.isHittable)
        close.tap()
    }

    func testPositionedCardBlocksBackgroundTapsUntilClosed() {
        launchPositionedSurvey(position: "top_center")
        let backgroundButton = app.buttons["background-action"]
        XCTAssertTrue(backgroundButton.exists)
        XCTAssertGreaterThan(backgroundButton.frame.minY, app.buttons["4"].frame.maxY)
        let backgroundPoint = backgroundButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        backgroundPoint.tap()
        XCTAssertEqual(app.staticTexts["background-taps"].label, "0")
        XCTAssertEqual(app.staticTexts["survey-status"].label, "shown")
        XCTAssertTrue(app.staticTexts["First question"].exists)
        app.buttons["posthog.survey.dismiss"].tap()
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "closed"),
            object: app.staticTexts["survey-status"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        backgroundPoint.tap()
        let tapped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "1"),
            object: app.staticTexts["background-taps"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [tapped], timeout: 5), .completed)
    }

    func testPositionedCardCloseWorksInProductionWindow() {
        app.launchEnvironment = ["SURVEY_POSITION": "top_center"]
        app.launch()
        let status = app.staticTexts["survey-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "shown"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed)
        let close = app.buttons["posthog.survey.dismiss"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "closed"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    func testOptionalQuestionCanStillSkipWithExplicitSubmission() {
        launch(kind: "number", flag: "false", optional: true)
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        assertQuestion("Second question")
        assertAnswers("0:nil")
    }

    private func launchPositionedSurvey(position: String, longContent: Bool = false, windowHeight: Int? = nil) {
        app.launchEnvironment = [
            "SURVEY_POSITION": position,
            "SURVEY_KIND": longContent ? "single" : "number",
            "SURVEY_SKIP": longContent ? "false" : "true",
            "SURVEY_LONG_CONTENT": String(longContent),
        ]
        if let windowHeight {
            app.launchEnvironment["SURVEY_WINDOW_HEIGHT"] = String(windowHeight)
        }
        app.launch()
        XCTAssertTrue(app.buttons["posthog.survey.dismiss"].waitForExistence(timeout: 5))
        assertQuestion("First question")
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
