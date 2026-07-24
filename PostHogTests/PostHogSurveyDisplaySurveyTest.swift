//
//  PostHogSurveyDisplaySurveyTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("Test manual displaySurvey API", .serialized)
class PostHogSurveyDisplaySurveyTest {
    let server: MockPostHogServer

    init() {
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
    }

    /// A delegate that records rendered survey IDs, so unit tests don't spin up real survey UI
    private final class RecordingSurveysDelegate: PostHogSurveysDelegate {
        var renderedSurveyIds: [String] = []

        func renderSurvey(
            _ survey: PostHogDisplaySurvey,
            onSurveyShown _: @escaping OnPostHogSurveyShown,
            onSurveyResponse _: @escaping OnPostHogSurveyResponse,
            onSurveyClosed _: @escaping OnPostHogSurveyClosed
        ) {
            renderedSurveyIds.append(survey.id)
        }

        func cleanupSurveys() {}
    }

    private let recordingDelegate = RecordingSurveysDelegate()

    func getTestSurvey(
        id: String = "test-survey-id",
        name: String = "Test Survey",
        type: PostHogSurveyType = .popover,
        conditions: PostHogSurveyConditions? = nil
    ) -> PostHogSurvey {
        PostHogSurvey(
            id: id,
            name: name,
            type: type,
            questions: [
                .open(PostHogOpenSurveyQuestion(
                    id: "qID1",
                    question: "What do you think about our product?",
                    description: "Please share your thoughts",
                    descriptionContentType: .text,
                    optional: false,
                    buttonText: nil,
                    originalQuestionIndex: 0,
                    branching: nil,
                    translations: nil
                )),
            ],
            featureFlagKeys: nil,
            linkedFlagKey: nil,
            targetingFlagKey: nil,
            internalTargetingFlagKey: nil,
            conditions: conditions,
            appearance: nil,
            currentIteration: nil,
            currentIterationStartDate: nil,
            startDate: Date(),
            endDate: nil,
            schedule: nil,
            translations: nil
        )
    }

    func eventConditions(_ eventName: String) -> PostHogSurveyConditions {
        PostHogSurveyConditions(
            url: nil,
            urlMatchType: nil,
            selector: nil,
            deviceTypes: nil,
            deviceTypesMatchType: nil,
            seenSurveyWaitPeriodInDays: nil,
            events: PostHogSurveyEventConditions(
                repeatedActivation: nil,
                values: [PostHogEventCondition(name: eventName, propertyFilters: nil)]
            ),
            actions: nil
        )
    }

    func getSut() -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config._surveysConfig.surveysDelegate = recordingDelegate
        config.flushAt = 1
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    func getSurveyIntegration(_ postHog: PostHogSDK) throws -> PostHogSurveyIntegration {
        PostHogSurveyIntegration.clearInstalls()
        let integration = PostHogSurveyIntegration()
        let installResult = integration.install(postHog)
        try #require(installResult == .installed)
        return integration
    }

    @Test("displaySurvey marks an API-type survey as active")
    func displaySurveyActivatesApiSurvey() throws {
        let postHog = getSut()
        let integration = try getSurveyIntegration(postHog)
        defer {
            integration.uninstall(postHog)
            postHog.close()
            postHog.reset()
        }

        let survey = getTestSurvey(id: "api-survey-id", type: .api)
        integration.setSurveys([survey])

        integration.displaySurvey(surveyId: "api-survey-id")

        #expect(integration.getActiveSurvey()?.id == "api-survey-id")
        #expect(integration.canShowNextSurvey() == false)
    }

    @Test("displaySurvey bypasses event trigger conditions")
    func displaySurveyBypassesEventTriggers() throws {
        let postHog = getSut()
        let integration = try getSurveyIntegration(postHog)
        defer {
            integration.uninstall(postHog)
            postHog.close()
            postHog.reset()
        }

        // survey with an event trigger that never fired
        let survey = getTestSurvey(id: "event-survey-id", conditions: eventConditions("some_event"))
        integration.setSurveys([survey])

        integration.displaySurvey(surveyId: "event-survey-id")

        #expect(integration.getActiveSurvey()?.id == "event-survey-id")
    }

    @Test("displaySurvey with an unknown ID does nothing")
    func displaySurveyUnknownIdDoesNothing() throws {
        let postHog = getSut()
        let integration = try getSurveyIntegration(postHog)
        defer {
            integration.uninstall(postHog)
            postHog.close()
            postHog.reset()
        }

        integration.setSurveys([getTestSurvey(id: "api-survey-id", type: .api)])

        integration.displaySurvey(surveyId: "unknown-id")

        #expect(integration.getActiveSurvey() == nil)
        #expect(integration.canShowNextSurvey() == true)
    }

    @Test("displaySurvey is ignored while another survey is active")
    func displaySurveyIgnoredWhileAnotherSurveyActive() throws {
        let postHog = getSut()
        let integration = try getSurveyIntegration(postHog)
        defer {
            integration.uninstall(postHog)
            postHog.close()
            postHog.reset()
        }

        let first = getTestSurvey(id: "first-survey-id")
        let second = getTestSurvey(id: "second-survey-id", type: .api)
        integration.setSurveys([first, second])
        integration.setShownSurvey(first)

        integration.displaySurvey(surveyId: "second-survey-id")

        #expect(integration.getActiveSurvey()?.id == "first-survey-id")
    }
}
