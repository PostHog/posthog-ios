//
//  PostHogSurveysConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/04/2025.
//

#if os(iOS)
    import Foundation

    @objc public class PostHogSurveysConfig: NSObject {
        public var surveysDelegate: PostHogSurveysDelegate?
    }

    @objc public protocol PostHogSurveysDelegate {
        @objc func renderSurvey(
            _ survey: PostHogDisplaySurvey,
            onSurveyShown: @escaping OnSurveyDelegateShown,
            onSurveyResponse: @escaping OnSurveyDelegateResponse,
            onSurveyClosed: @escaping OnSurveyDelegateClosed
        )
    }

    @objc public class PostHogDisplaySurvey: NSObject {
        public let title: String
        
        init(title: String) {
            self.title = title
        }
    }

    public typealias OnSurveyDelegateShown = (_ survey: PostHogDisplaySurvey) -> Void
    public typealias OnSurveyDelegateResponse = (_ survey: PostHogDisplaySurvey, _ index: Int, _ response: String) -> Int
    public typealias OnSurveyDelegateClosed = (_ survey: PostHogDisplaySurvey) -> Void

#endif
