//
//  PostHogSurveyIntegration+CancelEvents.swift
//  PostHog
//

#if os(iOS) || TESTING

    import Foundation

    extension PostHogSurveyIntegration {
        func storeSurveyEvents(
            _ events: [String: [(surveyId: String, condition: PostHogEventCondition)]],
            cancelEvents: [String: [(surveyId: String, condition: PostHogEventCondition)]]
        ) {
            eventsToSurveysLock.withLock {
                eventsToSurveys = events
                cancelEventsToSurveys = cancelEvents
            }
        }

        private struct CancelledSurveySnapshot {
            let survey: PostHogSurvey
            let attemptId: UUID?
            let wasShown: Bool
        }

        /// Drop event activation for surveys this capture cancels. A survey that is already
        /// showing is dismissed. One that is only waiting (delay, or not yet rendered) is
        /// cleared without a dismissed event, matching the web SDK's pending-survey cancel.
        func cancelSurveys(matching event: PostHogEvent) {
            let candidates = eventsToSurveysLock.withLock { cancelEventsToSurveys[event.event] } ?? []
            let matching = candidates.filter {
                matchPropertyFilters($0.condition.propertyFilters, eventProperties: event.properties)
            }
            guard !matching.isEmpty else { return }

            for candidate in matching {
                eventActivatedSurveysLock.withLock {
                    eventActivatedSurveys.removeValue(forKey: candidate.surveyId)
                }
                dismissCancelledSurvey(candidate.surveyId)
            }
        }

        private func dismissCancelledSurvey(_ surveyId: String) {
            let snapshot: CancelledSurveySnapshot? = activeSurveyLock.withLock {
                guard let activeSurvey, activeSurvey.id == surveyId else { return nil }
                return CancelledSurveySnapshot(
                    survey: activeSurvey,
                    attemptId: activeSurveyAttemptId,
                    wasShown: activeSurveyWasShown
                )
            }
            guard let snapshot else { return }

            #if os(iOS)
                if let delegate = config?._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate {
                    switch delegate.cancelSurveyIfPresented(surveyId) {
                    case .dismissed:
                        return
                    case .cancelledPending, .notPresented:
                        break
                    }
                }
            #endif

            if snapshot.wasShown {
                handleSurveyClosed(survey: snapshot.survey.toDisplaySurvey(), attemptId: snapshot.attemptId)
            } else {
                clearActiveSurvey()
            }
        }
    }
#endif
