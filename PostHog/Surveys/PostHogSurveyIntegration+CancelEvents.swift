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

            // Capture can call this off the main thread. Pending presentation and
            // SurveyDisplayController publish on the main queue, same as the other
            // display and reset paths.
            let apply = { [weak self] in
                guard let self else { return }
                // Reset can replace this attempt while the hop to main is queued.
                // The replacement must keep its reservation and its pending UI.
                guard self.activeSurveyLock.withLock({
                    self.activeSurvey?.id == snapshot.survey.id && self.activeSurveyAttemptId == snapshot.attemptId
                }) else { return }

                #if os(iOS)
                    if let delegate = self.config?._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate {
                        switch delegate.cancelSurveyIfPresented(surveyId) {
                        case .dismissed:
                            return
                        case .cancelledPending, .notPresented:
                            break
                        }
                    }
                #endif

                if snapshot.wasShown {
                    self.handleSurveyClosed(survey: snapshot.survey.toDisplaySurvey(), attemptId: snapshot.attemptId)
                } else {
                    self.clearActiveSurveyIfCurrent(surveyId: snapshot.survey.id, attemptId: snapshot.attemptId)
                }
            }

            #if os(iOS)
                if Thread.isMainThread {
                    apply()
                } else {
                    // capture calls this directly. Waiting for main here deadlocks when
                    // main is itself waiting on the thread that captured the cancel.
                    DispatchQueue.main.async(execute: apply)
                }
            #else
                apply()
            #endif
        }
    }
#endif
