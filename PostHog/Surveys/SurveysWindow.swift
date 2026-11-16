//
//  SurveysWindow.swift
//  PostHog
//
//  Created by Ioannis Josephides on 06/03/2025.
//

#if os(iOS)
    import SwiftUI
    import UIKit

    @available(iOS 15.0, *)
    final class SurveysWindow: PassthroughWindow {
        private let displayController: SurveyDisplayController?

        override var allowsBackgroundInteraction: Bool {
            displayController?.displayedSurvey == nil
        }

        init(controller: SurveyDisplayController, scene: UIWindowScene) {
            displayController = controller
            super.init(windowScene: scene)
            let rootView = SurveysRootView().environmentObject(controller)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = .clear
            rootViewController = hostingController
        }

        required init?(coder _: NSCoder) {
            displayController = nil
            super.init(frame: .zero)
        }
    }

    class PassthroughWindow: UIWindow {
        var allowsBackgroundInteraction: Bool { true }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard
                let hitView = super.hitTest(point, with: event),
                let rootView = rootViewController?.view
            else {
                return nil
            }

            guard hitView == rootView else { return hitView }

            // SwiftUI can return its root even when an embedded hosting view contains the hit.
            for subview in rootView.subviews.reversed() {
                if let hit = subview.hitTest(subview.convert(point, from: self), with: event) {
                    return hit
                }
            }
            return allowsBackgroundInteraction ? nil : rootView
        }
    }

#endif
