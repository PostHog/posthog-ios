//
//  PostHogAutocaptureEventTrackerSpec.swift
//  PostHog
//
//  Created by Yiannis Josephides on 31/10/2024.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("PostHogAutocaptureEventTracker", .serialized, .resetsGlobalState)
    @MainActor
    struct PostHogAutocaptureEventTrackerSpec {
        @Suite("when generating event data", .serialized)
        @MainActor
        struct GeneratingEventData {
            @Test("should correctly create event data for UIView")
            func eventDataForUIView() throws {
                let view = UIView()
                let eventData = try #require(view.eventData)

                #expect(eventData.viewHierarchy.count == 1)
            }

            @Test("should correctly create event data for UIView with view hierarchy")
            func eventDataForUIViewWithViewHierarchy() throws {
                let superview = UIView()
                let button = UIButton()
                superview.addSubview(button)
                let eventData = try #require(button.eventData)

                #expect(eventData.viewHierarchy.count == 2)
                #expect(eventData.screenName == nil)
            }

            @Test("when sanitizing text for autocapture text should be trimmed")
            func sanitizedTextIsTrimmed() throws {
                let button = UIButton()
                button.setTitle("   Hello, world! 🌎   ", for: .normal)
                let eventData = try #require(button.eventData)

                #expect(eventData.value == "Hello, world! 🌎")
            }

            @Test("when sanitizing text for autocapture text should be limited")
            func sanitizedTextIsLimited() throws {
                let button = UIButton()
                button.setTitle(String(repeating: "b", count: 300), for: .normal)
                let eventData = try #require(button.eventData)

                #expect(eventData.value == String(repeating: "b", count: 255) + "...")
            }
        }

        @Suite("shouldTrack method", .serialized)
        @MainActor
        struct ShouldTrack {
            @Test("should not track hidden views")
            func doesNotTrackHiddenViews() {
                let view = UIView()
                view.isHidden = true
                #expect(view.eventData == nil)
            }

            @Test("should not track views without user interaction enabled")
            func doesNotTrackNonInteractiveViews() {
                let view = UIView()
                view.isUserInteractionEnabled = false
                #expect(view.eventData == nil)
            }

            @Test("should not track views marked as ph-no-capture")
            func doesNotTrackNoCaptureViews() {
                let view = UIView()
                view.accessibilityIdentifier = "ph-no-capture" // example condition to make `isNoCapture` return true
                #expect(view.eventData == nil)
            }

            @Test("should track views that are visible and interactive")
            func tracksVisibleInteractiveViews() {
                let view = UIView()
                view.isHidden = false
                view.isUserInteractionEnabled = true
                #expect(view.eventData != nil)
            }
        }
    }

#endif
