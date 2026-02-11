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

    @Suite("PostHogAutocaptureEventTracker Tests")
    struct PostHogAutocaptureEventTrackerSpec {
        @Suite("when generating event data")
        struct WhenGeneratingEventData {
            @Test("should correctly create event data for UIView")
            @MainActor
            func shouldCorrectlyCreateEventDataForUIView() {
                let view = UIView()
                let eventData = view.eventData!

                #expect(eventData.viewHierarchy.count == 1)
            }

            @Test("should correctly create event data for UIView with view hierarchy")
            @MainActor
            func shouldCorrectlyCreateEventDataForUIViewWithViewHierarchy() {
                let superview = UIView()
                let button = UIButton()
                superview.addSubview(button)
                let eventData = button.eventData!

                #expect(eventData.viewHierarchy.count == 2)
                #expect(eventData.screenName == nil)
            }

            @Test("when sanitizing text for autocapture text should be trimmed")
            @MainActor
            func whenSanitizingTextForAutocaptureTextShouldBeTrimmed() {
                let button = UIButton()
                button.setTitle("   Hello, world! 🌎   ", for: .normal)
                let eventData = button.eventData!

                #expect(eventData.value == "Hello, world! 🌎")
            }

            @Test("when sanitizing text for autocapture text should be limited")
            @MainActor
            func whenSanitizingTextForAutocaptureTextShouldBeLimited() {
                let button = UIButton()
                button.setTitle(String(repeating: "b", count: 300), for: .normal)
                let eventData = button.eventData!

                #expect(eventData.value == String(repeating: "b", count: 255) + "...")
            }
        }

        @Suite("shouldTrack method")
        struct ShouldTrackMethod {
            @Test("should not track hidden views")
            @MainActor
            func shouldNotTrackHiddenViews() {
                let view = UIView()
                view.isHidden = true
                #expect(view.eventData == nil)
            }

            @Test("should not track views without user interaction enabled")
            @MainActor
            func shouldNotTrackViewsWithoutUserInteractionEnabled() {
                let view = UIView()
                view.isUserInteractionEnabled = false
                #expect(view.eventData == nil)
            }

            @Test("should not track views marked as ph-no-capture")
            @MainActor
            func shouldNotTrackViewsMarkedAsPhNoCapture() {
                let view = UIView()
                view.accessibilityIdentifier = "ph-no-capture" // example condition to make `isNoCapture` return true
                #expect(view.eventData == nil)
            }

            @Test("should track views that are visible and interactive")
            @MainActor
            func shouldTrackViewsThatAreVisibleAndInteractive() {
                let view = UIView()
                view.isHidden = false
                view.isUserInteractionEnabled = true
                #expect(view.eventData != nil)
            }
        }
    }

#endif
