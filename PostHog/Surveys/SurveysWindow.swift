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

            guard hitView == rootView else { return hitView }

            // SwiftUI can return its root even when an embedded hosting view contains the hit.
            for subview in rootView.subviews.reversed() {
                if let hit = subview.hitTest(subview.convert(point, from: self), with: event) {
                    return hit
                }
            }
            return nil
        }
    }

#endif
