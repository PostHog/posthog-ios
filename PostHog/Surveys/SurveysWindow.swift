//
//  SurveysWindow.swift
//  PostHog
//
//  Created by Ioannis Josephides on 06/03/2025.
//

#if os(iOS)
    import SwiftUI
    import UIKit

    final class SurveysWindow: PassthroughWindow {
        init(surveysManager: SurveysDisplayController, scene: UIWindowScene) {
            super.init(windowScene: scene)
            let rootView = SurveysRootView().environmentObject(surveysManager)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = .clear
            rootViewController = hostingController
        }

        required init?(coder _: NSCoder) {
            super.init(frame: .zero)
        }
    }

    class PassthroughWindow: UIWindow {
        override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard
                let hitView = super.hitTest(point, with: event),
                let rootView = rootViewController?.view
            else {
                return nil
            }

            // Hack for known hit test issue on iOS 18
            // see: https://developer.apple.com/forums/thread/762292
            if #available(iOS 18, *) {
                for subview in rootView.subviews.reversed() {
                    let convertedPoint = subview.convert(point, from: rootView)
                    if subview.hitTest(convertedPoint, with: event) != nil {
                        return hitView
                    }
                }
                return nil
            } else {
                // if test comes back as our own view, ignore (this is the passthrough part)
                return hitView == rootView ? nil : hitView
            }
        }
    }

#endif
