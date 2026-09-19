//
//  AutocaptureEventProcessing.swift
//  PostHog
//
//  Created by Yiannis Josephides on 30/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import Foundation

    protocol AutocaptureEventProcessing: AnyObject {
        var captureSwiftUIElementInteractions: Bool { get }
        func process(source: PostHogAutocaptureEventTracker.EventSource, event: PostHogAutocaptureEventTracker.EventData)
    }

    extension AutocaptureEventProcessing {
        var captureSwiftUIElementInteractions: Bool { false }
    }
#endif
