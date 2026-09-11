import Foundation

#if os(iOS) || TESTING
    struct SurveyProgress: Codable {
        var version = 2
        let resetEpoch: String
        let submissionId: String
        let questionOrder: [String]
        var questionIndex = 0
        var responses: [String: StoredSurveyResponse] = [:]
        var questionText: [String: String] = [:]
        var language: String?

        static func questionOrder(for survey: PostHogSurvey) -> [String] {
            survey.questions.map { question in
                let kind: String
                switch question {
                case .open: kind = "open"
                case .link: kind = "link"
                case .rating: kind = "rating"
                case .singleChoice: kind = "single_choice"
                case .multipleChoice: kind = "multiple_choice"
                case .unknown: kind = "unknown"
                }
                return "\(kind):\(question.id)"
            }
        }
    }

    struct StoredSurveyResponse: Codable {
        let type: Int
        let text: String?
        let rating: Int?
        let choices: [String]?
        let clicked: Bool?

        init(_ response: PostHogSurveyResponse) {
            type = response.type.rawValue
            text = response.textValue
            rating = response.ratingValue
            choices = response.selectedOptions
            clicked = response.linkClicked
        }

        var response: PostHogSurveyResponse? {
            switch PostHogSurveyResponseType(rawValue: type) {
            case .openEnded: return .openEnded(text)
            case .rating: return .rating(rating)
            case .singleChoice: return .singleChoice(choices?.first)
            case .multipleChoice: return .multipleChoice(choices)
            case .link: return .link(clicked ?? false)
            case nil: return nil
            }
        }
    }

    final class SurveyProgressStore {
        private let storage: PostHogStorage

        init(storage: PostHogStorage) {
            self.storage = storage
        }

        private func key(_ survey: PostHogSurvey) -> String {
            "\(survey.id)/\(survey.currentIteration ?? 0)"
        }

        func load(_ survey: PostHogSurvey) -> SurveyProgress? {
            storage.withSurveyState { generation in
                let records = storage.getDictionary(forKey: .surveyProgress) ?? [:]
                guard storage.isSurveyGenerationCurrent(generation) else { return nil }
                guard let json = records[key(survey)] else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: json),
                      let progress = try? JSONDecoder().decode(SurveyProgress.self, from: data),
                      progress.version == 2, progress.resetEpoch == generation, !progress.submissionId.isEmpty,
                      survey.questions.indices.contains(progress.questionIndex),
                      progress.questionOrder == SurveyProgress.questionOrder(for: survey),
                      progress.responses.values.allSatisfy({ $0.response != nil })
                else {
                    removeLocked(survey)
                    return nil
                }
                return progress
            }
        }

        func save(_ progress: SurveyProgress, for survey: PostHogSurvey) {
            storage.withSurveyState { generation in
                guard progress.resetEpoch == generation,
                      let data = try? JSONEncoder().encode(progress),
                      let json = try? JSONSerialization.jsonObject(with: data) else { return }
                var records = storage.getDictionary(forKey: .surveyProgress) ?? [:]
                guard storage.isSurveyGenerationCurrent(generation) else { return }
                records[key(survey)] = json
                storage.setDictionary(forKey: .surveyProgress, contents: records)
            }
        }

        func reconcile(_ surveys: [PostHogSurvey]) {
            storage.withSurveyState { generation in
                let keys = Set(surveys.filter(\.isActive).map(key))
                let records = storage.getDictionary(forKey: .surveyProgress) ?? [:]
                guard storage.isSurveyGenerationCurrent(generation) else { return }
                storage.setDictionary(forKey: .surveyProgress, contents: records.filter { entry in
                    (entry.key as? String).map(keys.contains) ?? false
                })
            }
        }

        func remove(_ survey: PostHogSurvey) {
            storage.withSurveyState { _ in removeLocked(survey) }
        }

        private func removeLocked(_ survey: PostHogSurvey) {
            let generation = storage.withSurveyState { $0 }
            var records = storage.getDictionary(forKey: .surveyProgress) ?? [:]
            guard storage.isSurveyGenerationCurrent(generation) else { return }
            records.removeValue(forKey: key(survey))
            storage.setDictionary(forKey: .surveyProgress, contents: records)
        }
    }
#endif
