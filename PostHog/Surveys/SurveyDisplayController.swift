//
//  SurveyDisplayController.swift
//  PostHog
//
//  Created by Ioannis Josephides on 07/03/2025.
//

#if os(iOS) || TESTING
    import SwiftUI

    final class SurveyDisplayController: ObservableObject {
        typealias SurveyShownHandler = (_ survey: PostHogSurvey) -> Void
        typealias SurveyResponseHandler = (_ survey: PostHogSurvey, _ responses: [String: PostHogSurveyResponse], _ completed: Bool) -> Void
        typealias SurveyClosedHandler = (_ survey: PostHogSurvey, _ completed: Bool) -> Void

        @Published var displayedSurvey: PostHogSurvey?
        @Published var isSurveyCompleted: Bool = false
        @Published var currentQuestionIndex: Int?
        private var questionResponses: [String: PostHogSurveyResponse] = [:]

        private let onSurveyShown: SurveyShownHandler
        private let onSurveyResponse: SurveyResponseHandler
        private let onSurveyClosed: SurveyClosedHandler

        private let kSurveyResponseKey = "$survey_response"

        init(
            onSurveyShown: @escaping SurveyShownHandler,
            onSurveyResponse: @escaping SurveyResponseHandler,
            onSurveyClosed: @escaping SurveyClosedHandler
        ) {
            self.onSurveyShown = onSurveyShown
            self.onSurveyResponse = onSurveyResponse
            self.onSurveyClosed = onSurveyClosed
        }

        func showSurvey(_ survey: PostHogSurvey) {
            guard displayedSurvey == nil else {
                hedgeLog("[Surveys] Already displaying a survey. Skipping")
                return
            }

            displayedSurvey = survey
            isSurveyCompleted = false
            currentQuestionIndex = 0
            onSurveyShown(survey)
        }

        func onNextQuestion(index: Int, response: PostHogSurveyResponse) {
            guard let displayedSurvey else { return }

            // update question responses
            questionResponses[getResponseKey(for: index)] = response
            // get next step
            let nextQuestion = getNextSurveyStep(survey: displayedSurvey, currentQuestionIndex: index)

            switch nextQuestion {
            case let .index(nextIndex):
                currentQuestionIndex = nextIndex
                isSurveyCompleted = false
            case .end:
                // stay on current step and mark survey as ended
                isSurveyCompleted = true
            }

            onSurveyResponse(displayedSurvey, questionResponses, isSurveyCompleted)
        }

        // User dismissed survey
        func dismissSurvey() {
            if let survey = displayedSurvey {
                onSurveyClosed(survey, isSurveyCompleted)
            }
            displayedSurvey = nil
            isSurveyCompleted = false
            currentQuestionIndex = nil
            questionResponses = [:]
        }

        func canShowNextSurvey() -> Bool {
            displayedSurvey == nil
        }

        /// Returns next question index
        /// - Parameters:
        ///   - survey: The survey which contains the question
        ///   - currentQuestionIndex: The current question index
        /// - Returns: The next question `.index()` if found, or `.end` survey reach the end
        private func getNextSurveyStep(
            survey: PostHogSurvey,
            currentQuestionIndex: Int
        ) -> NextSurveyQuestion {
            let question = survey.questions[currentQuestionIndex]
            let nextQuestionIndex = min(currentQuestionIndex + 1, survey.questions.count - 1)

            guard let branching = question.branching else {
                return currentQuestionIndex == survey.questions.count - 1 ? .end : .index(nextQuestionIndex)
            }

            switch branching {
            case .end:
                return .end

            case let .specificQuestion(index):
                return .index(min(index, survey.questions.count - 1))

            case let .responseBased(responseValues):
                return getResponseBasedNextQuestionIndex(
                    survey: survey,
                    question: question,
                    response: questionResponses[getResponseKey(for: currentQuestionIndex)],
                    responseValues: responseValues
                ) ?? .index(nextQuestionIndex)

            case .next:
                return .index(nextQuestionIndex)
            }
        }

        private func getResponseKey(for index: Int) -> String {
            index == 0 ? kSurveyResponseKey : "\(kSurveyResponseKey)_\(index)"
        }

        /// Returns next question index based on response value (from responseValues dictionary)
        ///
        /// - Parameters:
        ///   - survey: The survey which contains the question
        ///   - question: The current question
        ///   - response: The response to the current question
        ///   - responseValues: The response values dictionary
        /// - Returns: The next index if found in the `responseValues`
        private func getResponseBasedNextQuestionIndex(
            survey: PostHogSurvey,
            question: PostHogSurveyQuestion,
            response: PostHogSurveyResponse?,
            responseValues: [String: Any]
        ) -> NextSurveyQuestion? {
            guard let response else {
                hedgeLog("[Surveys] Got response based branching, but missing the actual response.")
                return nil
            }

            switch (question, response) {
            case let (.singleChoice(singleChoiceQuestion), .singleChoice(singleChoiceResponse)):
                var responseIndex = singleChoiceQuestion.choices.firstIndex(of: singleChoiceResponse ?? "")

                if responseIndex == nil, singleChoiceQuestion.hasOpenChoice == true {
                    // if the response is not found in the choices, it must be the open choice, which is always the last choice
                    responseIndex = singleChoiceQuestion.choices.count - 1
                }

                if let responseIndex, let nextIndex = responseValues["\(responseIndex)"] {
                    return processBranchingStep(nextIndex: nextIndex, totalQuestions: survey.questions.count)
                }

                hedgeLog("[Surveys] Could not find response index for specific question.")
                return nil

            case let (.rating(ratingQuestion), .rating(responseInt)):
                if let responseInt,
                   let ratingBucket = getRatingBucketForResponseValue(scale: ratingQuestion.scale, value: responseInt),
                   let nextIndex = responseValues[ratingBucket]
                {
                    return processBranchingStep(nextIndex: nextIndex, totalQuestions: survey.questions.count)
                }
                hedgeLog("[Surveys] Could not get response bucket for rating question.")
                return nil

            default:
                hedgeLog("[Surveys] Got response based branching for an unsupported question type.")
                return nil
            }
        }

        /// Returns next question index based on a branching step result
        /// - Parameters:
        ///   - nextIndex: The next index to process
        ///   - totalQuestions: The total number of questions in the survey
        /// - Returns: The next question index if found, or nil if not
        private func processBranchingStep(nextIndex: Any, totalQuestions: Int) -> NextSurveyQuestion? {
            if let nextIndex = nextIndex as? Int {
                return .index(min(nextIndex, totalQuestions - 1))
            }
            if let nextIndex = nextIndex as? String, nextIndex.lowercased() == "end" {
                return .end
            }
            return nil
        }

        // Gets the response bucket for a given rating response value, given the scale.
        // For example, for a scale of 3, the buckets are "negative", "neutral" and "positive".
        private func getRatingBucketForResponseValue(scale: Int, value: Int) -> String? {
            // swiftlint:disable:previous cyclomatic_complexity
            // Validate input ranges
            switch scale {
            case 3 where RatingBucket.threePointRange.contains(value):
                switch value {
                case BucketThresholds.ThreePoint.negatives: return RatingBucket.negative
                case BucketThresholds.ThreePoint.neutrals: return RatingBucket.neutral
                default: return RatingBucket.positive
                }

            case 5 where RatingBucket.fivePointRange.contains(value):
                switch value {
                case BucketThresholds.FivePoint.negatives: return RatingBucket.negative
                case BucketThresholds.FivePoint.neutrals: return RatingBucket.neutral
                default: return RatingBucket.positive
                }

            case 7 where RatingBucket.sevenPointRange.contains(value):
                switch value {
                case BucketThresholds.SevenPoint.negatives: return RatingBucket.negative
                case BucketThresholds.SevenPoint.neutrals: return RatingBucket.neutral
                default: return RatingBucket.positive
                }

            case 10 where RatingBucket.tenPointRange.contains(value):
                switch value {
                case BucketThresholds.TenPoint.detractors: return RatingBucket.detractors
                case BucketThresholds.TenPoint.passives: return RatingBucket.passives
                default: return RatingBucket.promoters
                }

            default:
                hedgeLog("[Surveys] Cannot get rating bucket for invalid scale: \(scale). The scale must be one of: 3 (1-3), 5 (1-5), 7 (1-7), 10 (0-10).")
                return nil
            }
        }
    }

    enum NextSurveyQuestion {
        case index(Int)
        case end
    }

    private enum RatingBucket {
        // Bucket names
        static let negative = "negative"
        static let neutral = "neutral"
        static let positive = "positive"
        static let detractors = "detractors"
        static let passives = "passives"
        static let promoters = "promoters"

        // Scale ranges
        static let threePointRange = 1 ... 3
        static let fivePointRange = 1 ... 5
        static let sevenPointRange = 1 ... 7
        static let tenPointRange = 0 ... 10
    }

    private enum BucketThresholds {
        enum ThreePoint {
            static let negatives = 1 ... 1
            static let neutrals = 2 ... 2
        }

        enum FivePoint {
            static let negatives = 1 ... 2
            static let neutrals = 3 ... 3
        }

        enum SevenPoint {
            static let negatives = 1 ... 3
            static let neutrals = 4 ... 4
        }

        enum TenPoint {
            static let detractors = 0 ... 6
            static let passives = 7 ... 8
        }
    }
#endif
