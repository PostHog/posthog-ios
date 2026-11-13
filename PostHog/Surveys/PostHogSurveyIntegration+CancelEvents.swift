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

        /// Drop unconsumed activation and cancel the built-in popup delay, if pending.
        /// Shown surveys and attempts handed to a custom delegate retain their callbacks.
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
                cancelPendingSurveyDisplay(candidate.surveyId)
            }
        }

        private func cancelPendingSurveyDisplay(_ surveyId: String) {
            #if os(iOS)
                guard let delegate = config?._surveysConfig.surveysDelegate as? PostHogSurveysDefaultDelegate else { return }
                let attemptId = activeSurveyLock.withLock { () -> UUID? in
                    guard activeSurvey?.id == surveyId else { return nil }
                    return activeSurveyAttemptId
                }
                guard let attemptId else { return }

                let apply = { [weak self] in
                    guard let self,
                          self.activeSurveyLock.withLock({ self.activeSurveyAttemptId == attemptId })
                    else { return }
                    _ = delegate.cancelPendingSurveyIfPresented(surveyId)
                }

                if Thread.isMainThread {
                    apply()
                } else {
                    DispatchQueue.main.async(execute: apply)
                }
            #endif
        }
    }
#endif
