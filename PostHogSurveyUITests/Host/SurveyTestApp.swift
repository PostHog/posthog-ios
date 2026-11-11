@testable import PostHog
import SwiftUI
import UIKit

@main
struct SurveyTestApp: App {
    @StateObject private var fixture = SurveyFixture()

    var body: some Scene {
        WindowGroup {
            VStack {
                if fixture.position == nil {
                    Text(fixture.answers.isEmpty ? "none" : fixture.answers.joined(separator: "|"))
                        .accessibilityIdentifier("answers")
                    SurveySheet(displayManager: fixture.controller, fallbackSurvey: fixture.survey)
                } else {
                    Text(fixture.status)
                        .accessibilityIdentifier("survey-status")
                        .onAppear { fixture.presentProductionWindow() }
                }
            }
        }
    }
}

// Fixtures and the response recorder live in the test host; all controls, state and
// transitions under test belong to the SDK's SurveySheet and SurveyDisplayController.
private final class SurveyFixture: ObservableObject {
    let controller = SurveyDisplayController()
    let survey: PostHogDisplaySurvey
    let position: String?
    @Published var answers: [String] = []
    @Published var status = ""
    private var productionWindow: SurveysWindow?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let kind = environment["SURVEY_KIND"] ?? "number"
        let flag = environment["SURVEY_SKIP"] ?? "true"
        position = environment["SURVEY_POSITION"]
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
        if environment["SURVEY_LONG_CONTENT"] == "true" {
            first["choices"] = (1 ... 30).map { "Choice \($0)" }
        }
        var second = first
        second["choices"] = ["First", "Second", "Other"]
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
            appearance: position.map(Self.appearance(position:)), startDate: nil, endDate: nil
        )
        controller.onSurveyResponse = { [weak self] _, index, response in
            let value = response.ratingValue.map(String.init)
                ?? response.selectedOptions?.joined(separator: ",") ?? "nil"
            self?.answers.append("\(index):\(value)")
            return PostHogNextSurveyQuestion(questionIndex: 2, isSurveyCompleted: index == 2)
        }
        controller.onSurveyClosed = { [weak self] _ in
            self?.status = "closed"
        }
        if position == nil {
            controller.showSurvey(survey)
        }
    }

    /// Presents through `SurveysWindow`, the same passthrough window production uses.
    func presentProductionWindow() {
        guard productionWindow == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.productionWindow == nil else { return }
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                self.status = "no-scene"
                return
            }
            let window = SurveysWindow(controller: self.controller, scene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.windowLevel = .alert
            window.makeKeyAndVisible()
            self.productionWindow = window
            self.controller.showSurvey(self.survey)
            self.status = "shown"
        }
    }

    private static func appearance(position: String) -> PostHogDisplaySurveyAppearance {
        PostHogDisplaySurveyAppearance(
            fontFamily: nil,
            backgroundColor: nil,
            borderColor: nil,
            submitButtonColor: nil,
            submitButtonText: nil,
            submitButtonTextColor: nil,
            textColor: nil,
            descriptionTextColor: nil,
            ratingButtonColor: nil,
            ratingButtonActiveColor: nil,
            inputBackground: nil,
            inputTextColor: nil,
            placeholder: nil,
            surveyPopupDelaySeconds: nil,
            displayThankYouMessage: false,
            thankYouMessageHeader: nil,
            thankYouMessageDescription: nil,
            thankYouMessageDescriptionContentType: nil,
            thankYouMessageCloseButtonText: nil,
            position: position
        )
    }
}
