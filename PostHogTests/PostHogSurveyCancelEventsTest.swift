import Foundation
@testable import PostHog
import Testing

@Suite("Survey cancel events", .serialized)
struct PostHogSurveyCancelEventsTest {
    private func makeIntegration() throws -> (PostHogSDK, PostHogSurveyIntegration) {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.disableRemoteConfigForTesting = true
        config.flushAt = 1
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        PostHogStorage(config).reset()
        let postHog = PostHogSDK.with(config)
        PostHogSurveyIntegration.clearInstalls()
        let integration = PostHogSurveyIntegration()
        let installResult = integration.install(postHog)
        try #require(installResult == .installed)
        integration.stop()
        return (postHog, integration)
    }

    private func load(_ integration: PostHogSurveyIntegration) {
        let survey: [String: Any] = [
            "id": "cancel-survey",
            "name": "Cancel survey",
            "type": "popover",
            "questions": [[
                "id": "q",
                "type": "open",
                "question": "How was checkout?",
            ]],
            "conditions": [
                "events": ["values": [["name": "show_survey"]]],
                "cancel_events": ["values": [["name": "checkout_completed"]]],
            ],
            "start_date": "2024-01-01T00:00:00.000Z",
        ]
        integration.decodeAndSetSurveys(remoteConfig: ["surveys": [survey]]) { _ in }
    }

    @Test("a cancel event drops an activation that has not been shown")
    func cancelClearsActivation() throws {
        let (postHog, integration) = try makeIntegration()
        defer {
            postHog.close()
            postHog.reset()
        }
        load(integration)
        let placeholder = try #require(integration.decodeSurveys(from: [
            "surveys": [[
                "id": "placeholder",
                "name": "Placeholder",
                "type": "popover",
                "questions": [["id": "p", "type": "open", "question": "Hold"]],
                "start_date": "2024-01-01T00:00:00.000Z",
            ]],
        ]).first)
        integration.setShownSurvey(placeholder)

        integration.testOnEvent(event: PostHogEvent(event: "show_survey", distinctId: "user", properties: [:], timestamp: Date()))
        #expect(integration.testIsEventActivated(surveyId: "cancel-survey"))

        integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))
        #expect(!integration.testIsEventActivated(surveyId: "cancel-survey"))
    }

    @Test("a cancel event dismisses a survey that is already on screen")
    func cancelDismissesShownSurvey() throws {
        let (postHog, integration) = try makeIntegration()
        defer {
            postHog.close()
            postHog.reset()
        }
        var events: [PostHogEvent] = []
        postHog.config.setBeforeSend { events.append($0)
            return nil
        }
        load(integration)
        let survey = try #require(integration.decodeSurveys(from: [
            "surveys": [[
                "id": "cancel-survey",
                "name": "Cancel survey",
                "type": "popover",
                "questions": [[
                    "id": "q",
                    "type": "open",
                    "question": "How was checkout?",
                ]],
                "conditions": [
                    "events": ["values": [["name": "show_survey"]]],
                    "cancel_events": ["values": [["name": "checkout_completed"]]],
                ],
                "start_date": "2024-01-01T00:00:00.000Z",
            ]],
        ]).first)
        integration.setShownSurvey(survey)
        integration.testSurveyCallbacks().shown(survey.toDisplaySurvey())

        integration.testOnEvent(event: PostHogEvent(event: "checkout_completed", distinctId: "user", properties: [:], timestamp: Date()))

        #expect(events.contains { $0.event == "survey dismissed" })
        #expect(integration.canShowNextSurvey())
    }
}
