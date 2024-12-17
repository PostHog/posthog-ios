//
//  PostHogAutocaptureEventTrackerSpec.swift
//  PostHog
//
//  Created by Yiannis Josephides on 31/10/2024.
//

#if os(iOS)
    import Foundation
    import Nimble
    @testable import PostHog
    import Quick
    import UIKit

    class PostHogAutocaptureEventTrackerSpec: QuickSpec {
        override func spec() {
            context("when generating event data") {
                it("should correctly create event data for UIView") { @MainActor in
                    let view = UIView()
                    let eventData = view.eventData!

                    expect(eventData.viewHierarchy.first?.targetClass).to(equal("UIView"))
                    expect(eventData.viewHierarchy.count).to(equal(1))
                }

                it("should correctly create event data for UIView with view hierarchy") { @MainActor in
                    let superview = UIView()
                    let button = UIButton()
                    superview.addSubview(button)
                    let eventData = button.eventData!

                    expect(eventData.viewHierarchy.first?.targetClass).to(equal("UIButton"))
                    expect(eventData.viewHierarchy.count).to(equal(2))
                    expect(eventData.screenName).to(beNil())
                }

                it("when sanitizing text for autocapture text should be trimmed") { @MainActor in
                    let button = UIButton()
                    button.setTitle("   Hello, world! 🌎   ", for: .normal)
                    let eventData = button.eventData!

                    expect(eventData.value).to(equal("Hello, world! 🌎"))
                }

                it("when sanitizing text for autocapture text should be limited") { @MainActor in
                    let button = UIButton()
                    button.setTitle(String(repeating: "b", count: 300), for: .normal)
                    let eventData = button.eventData!

                    expect(eventData.value).to(equal(String(repeating: "b", count: 255) + "..."))
                }
            }

            context("shouldTrack method") {
                it("should not track hidden views") { @MainActor in
                    let view = UIView()
                    view.isHidden = true
                    expect(view.eventData).to(beNil())
                }

                it("should not track views without user interaction enabled") { @MainActor in
                    let view = UIView()
                    view.isUserInteractionEnabled = false
                    expect(view.eventData).to(beNil())
                }

                it("should not track views marked as ph-no-capture") { @MainActor in
                    let view = UIView()
                    view.accessibilityIdentifier = "ph-no-capture" // example condition to make `isNoCapture` return true
                    expect(view.eventData).to(beNil())
                }

                it("should track views that are visible and interactive") { @MainActor in
                    let view = UIView()
                    view.isHidden = false
                    view.isUserInteractionEnabled = true
                    expect(view.eventData).toNot(beNil())
                }
            }
        }
    }

#endif
