//
//  AutocaptureEventProcessing.swift
//  PostHog
//
//  Created by Yiannis Josephides on 30/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import Foundation

    protocol AutocaptureEventProcessing: AnyObject {
        func process(source: PostHogAutocaptureEventTracker.EventSource, event: PostHogAutocaptureEventTracker.EventData)
    }
#endif
