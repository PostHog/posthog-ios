@testable import PostHog
import SwiftUI

@main
struct SurveyTestApp: App {
    @StateObject private var fixture = SurveyFixture()

    var body: some Scene {
        WindowGroup {
            VStack {
                Text(fixture.answers.isEmpty ? "none" : fixture.answers.joined(separator: "|"))
                    .accessibilityIdentifier("answers")
                SurveySheet(displayManager: fixture.controller, fallbackSurvey: fixture.survey)
            }
        }
    }
}

// Fixtures and the response recorder live in the test host; all controls, state and
// transitions under test belong to the SDK's SurveySheet and SurveyDisplayController.
private final class SurveyFixture: ObservableObject {
    let controller = SurveyDisplayController()
    let survey: PostHogDisplaySurvey
    @Published var answers: [String] = []

    init() {
        let environment = ProcessInfo.processInfo.environment
        let kind = environment["SURVEY_KIND"] ?? "number"
        let flag = environment["SURVEY_SKIP"] ?? "true"
        let type = kind == "number" || kind == "emoji" ? "rating" : kind == "multiple" ? "multiple_choice" : "single_choice"
        var first: [String: Any] = [
            "id": "first", "question": "First question", "type": type,
            "display": kind, "scale": 5, "choices": ["First", "Second", "Other"],
            "hasOpenChoice": kind == "open", "buttonText": "Continue",
            "optional": environment["SURVEY_OPTIONAL"] == "true",
        ]
        if flag != "missing" {
            first["skipSubmitButton"] = flag == "true"
        }
        var second = first
        second["id"] = "second"
        second["question"] = "Second question"
        second["skipSubmitButton"] = false
        second["optional"] = false
        var skipped = first
        skipped["id"] = "skipped"
        skipped["question"] = "Skipped question"
        let questions = [first, skipped, second].map { json -> PostHogDisplaySurveyQuestion in
            // Invalid fixtures should fail launch rather than silently exercise a different UI.
            let data = try! JSONSerialization.data(withJSONObject: json)
            return try! PostHogApi.jsonDecoder.decode(PostHogSurveyQuestion.self, from: data).toDisplayQuestion()!
        }
        survey = PostHogDisplaySurvey(
            id: "ui-test", name: "UI test", questions: questions,
            appearance: nil, startDate: nil, endDate: nil
        )
        controller.onSurveyResponse = { [weak self] _, index, response in
            let value = response.ratingValue.map(String.init)
                ?? response.selectedOptions?.joined(separator: ",") ?? "nil"
            self?.answers.append("\(index):\(value)")
            return PostHogNextSurveyQuestion(questionIndex: 2, isSurveyCompleted: index == 2)
        }
        controller.showSurvey(survey)
    }
}
