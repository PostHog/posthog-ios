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
        init(controller: SurveyDisplayController, scene: UIWindowScene) {
            super.init(windowScene: scene)
            let rootView = SurveysRootView().environmentObject(controller)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = .clear
            rootViewController = hostingController
        }

        required init?(coder _: NSCoder) {
            super.init(frame: .zero)
        }
    }

    class PassthroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard
                let hitView = super.hitTest(point, with: event),
                let rootView = rootViewController?.view
            else {
                return nil
            }

            // if test comes back as our own view, ignore (this is the passthrough part)
            return hitView == rootView ? nil : hitView
        }
    }

#endif
