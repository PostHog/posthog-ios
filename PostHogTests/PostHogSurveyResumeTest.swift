import Foundation
@testable import PostHog
import Testing

#if os(iOS)
    extension PostHogSurveyEventsTest {
        @MainActor
        private func renderingSDK(resetStorage: Bool, language: String) -> (PostHogSDK, PostHogSurveyIntegration, SurveyDisplayController) {
            let postHog = getSut(resetStorage: resetStorage, installSurveys: false)
            postHog.config._surveys = true
            postHog.config._surveysConfig.overrideDisplayLanguage = language
            let integration = PostHogSurveyIntegration()
            postHog.addIntegration(integration)
            // Fixture surveys are supplied directly; background refresh must not replace them.
            integration.stop()
            integration.hasActiveSurveyWindow = { true }
            let controller = SurveyDisplayController()
            let delegate = PostHogSurveysDefaultDelegate()
            delegate.setDisplayControllerForTesting(controller)
            postHog.config._surveysConfig.surveysDelegate = delegate
            return (postHog, integration, controller)
        }

        private func branchingResumeSurvey(enabled: Bool?) throws -> PostHogSurvey {
            try partialResponseSurvey(enabled: enabled, properties: [
                "start_date": 0,
                "questions": [
                    ["id": "first", "type": "open", "question": "Original first?", "branching": ["type": "specific_question", "index": 2], "translations": ["fr": ["question": "Premiere question?"]]],
                    ["id": "skipped", "type": "open", "question": "Skipped?"],
                    ["id": "last", "type": "open", "question": "Last?", "translations": ["fr": ["question": "Derniere question?"]]],
                ],
                "translations": ["en": ["name": "English survey"], "fr": ["name": "French survey"]],
                "appearance": ["displayIntroScreen": true, "introScreenHeader": "Welcome", "displayThankYouMessage": false],
            ])
        }

        private func expectResumedCompletion(_ completed: PostHogEvent, submissionId: String) throws {
            #expect(completed.properties["$survey_response_first"] as? String == "Saved answer")
            #expect(completed.properties["$survey_response_last"] as? String == "New answer")
            #expect(completed.properties["$survey_response_skipped"] == nil)
            #expect(completed.properties["$survey_submission_id"] as? String == submissionId)
            #expect(completed.properties["$survey_completed"] as? Bool == true)
            #expect(completed.properties["$survey_language"] as? String == "fr")
            let questions = try #require(completed.properties["$survey_questions"] as? [[String: Any]])
            #expect(questions.count == 3)
            #expect(questions[0]["question"] as? String == "Original first?")
            #expect(questions[2]["question"] as? String == "Derniere question?")
        }

        private func expectResumedDismissal(_ dismissed: PostHogEvent, submissionId: String) throws {
            #expect(dismissed.properties["$survey_submission_id"] as? String == submissionId)
            #expect(dismissed.properties["$survey_language"] as? String == "en")
            #expect(dismissed.properties["$survey_response_first"] as? String == "Saved answer")
            #expect(dismissed.properties["$survey_response_last"] == nil)
            let questions = try #require(dismissed.properties["$survey_questions"] as? [[String: Any]])
            #expect(questions[0]["question"] as? String == "Original first?")
        }

        @MainActor
        @Test("a fresh SDK renders the saved branch and preserves answer attribution", arguments: [(true, false), (false, false), (nil, false), (true, true)] as [(Bool?, Bool)])
        func resumeAfterRestart(enabled: Bool?, dismiss: Bool) async throws {
            let survey = try branchingResumeSurvey(enabled: enabled)
            let (firstSDK, first, firstController) = renderingSDK(resetStorage: true, language: "en")
            defer { firstSDK.close() }
            let firstStorage = try #require(firstSDK.storage)
            let firstShown = AsyncLatch()
            var firstEvents: [PostHogEvent] = []
            firstSDK.config.setBeforeSend {
                firstEvents.append($0)
                if $0.event == "survey shown" { firstShown.signal() }
                return nil
            }
            first.setSurveys([survey])
            first.showNextSurvey()
            await firstShown.wait(timeout: 2)
            try #require(firstController.displayedSurvey != nil)
            #expect(firstController.currentQuestionIndex == 0)
            #expect(firstController.showingIntroScreen)
            firstController.dismissIntroScreen()
            firstController.onNextQuestion(index: firstController.currentQuestionIndex, response: .openEnded("Saved answer"))
            #expect(firstController.currentQuestionIndex == 2)
            let saved = try #require(SurveyProgressStore(storage: firstStorage).load(survey))
            #expect(firstEvents.map(\.event) == (enabled == true ? ["survey shown", "survey sent"] : ["survey shown"]))
            #expect(firstEvents.last?.properties["$survey_language"] as? String == "en")
            firstSDK.close()
            #expect(first.testActiveSubmissionId == nil)
            #expect(firstController.displayedSurvey == nil)

            let (secondSDK, resumed, controller) = renderingSDK(resetStorage: false, language: "fr")
            defer { secondSDK.close()
                secondSDK.reset()
            }
            let secondStorage = try #require(secondSDK.storage)
            #expect(secondStorage !== firstStorage)
            #expect(secondStorage.appFolderUrl == firstStorage.appFolderUrl)
            let shown = AsyncLatch()
            var events: [PostHogEvent] = []
            secondSDK.config.setBeforeSend {
                events.append($0)
                if $0.event == "survey shown" { shown.signal() }
                return nil
            }
            resumed.setSurveys([survey])
            resumed.showNextSurvey()
            await shown.wait(timeout: 2)
            let display = try #require(controller.displayedSurvey)
            #expect(display.name == "French survey")
            #expect(display.questions[0].question == "Premiere question?")
            #expect(controller.currentQuestionIndex == 2)
            #expect(display.questions[controller.currentQuestionIndex].id == "last")
            #expect(!controller.showingIntroScreen)
            #expect(events.map(\.event) == ["survey shown"])
            if dismiss {
                controller.dismissSurvey()
                #expect(events.map(\.event) == ["survey shown", "survey dismissed"])
                let dismissed = try #require(events.last)
                try expectResumedDismissal(dismissed, submissionId: saved.submissionId)
                #expect(SurveyProgressStore(storage: secondStorage).load(survey) == nil)
                return
            }
            controller.onNextQuestion(index: controller.currentQuestionIndex, response: .openEnded("New answer"))
            #expect(controller.isSurveyCompleted)
            #expect(controller.displayedSurvey == nil)
            #expect(events.map(\.event) == ["survey shown", "survey sent"])
            let completed = try #require(events.last)
            try expectResumedCompletion(completed, submissionId: saved.submissionId)
            #expect(SurveyProgressStore(storage: secondStorage).load(survey) == nil)
        }
    }
#endif
