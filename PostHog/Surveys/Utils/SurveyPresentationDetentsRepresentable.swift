//
//  SurveyPresentationDetentsRepresentable.swift
//  PostHog
//
//  Created by Ioannis Josephides on 22/03/2025.
//

#if os(iOS)

    import SwiftUI

    @available(iOS 15.0, *)
    struct SurveyPresentationDetentsRepresentable: UIViewControllerRepresentable {
        enum Detent: Hashable, Identifiable, Comparable {
            case medium
            case large
            case height(_ value: CGFloat)

            var toPresentationDetents: UISheetPresentationController.Detent {
                switch self {
                case .medium: .medium()
                case .large:
                    if #available(iOS 16.0, *) {
                        // almost large detent, so that background view is not scaled
                        .custom(identifier: id, resolver: { context in context.maximumDetentValue - 0.5 })
                    } else {
                        .large()
                    }
                case let .height(value):
                    if #available(iOS 16.0, *) {
                        if value > 0 {
                            .custom(identifier: id, resolver: { _ in value })
                        } else {
                            .medium()
                        }
                    } else {
                        .medium()
                    }
                }
            }

            var id: UISheetPresentationController.Detent.Identifier {
                switch self {
                case .medium: .init("com.apple.UIKit.medium")
                case .large:
                    if #available(iOS 16.0, *) {
                        .init("posthog.detent.almostLarge")
                    } else {
                        .init("com.apple.UIKit.large")
                    }
                case let .height(value):
                    if #available(iOS 16.0, *) {
                        if value > 0 {
                            .init("posthog.detent.customHeight.\(value)")
                        } else {
                            .init("com.apple.UIKit.medium")
                        }
                    } else {
                        .init("com.apple.UIKit.medium")
                    }
                }
            }
        }

        let detents: [Detent]

        func makeUIViewController(context _: Context) -> Controller {
            Controller(detents: detents)
        }

        func updateUIViewController(_ controller: Controller, context _: Context) {
            controller.detents = detents
            DispatchQueue.main.async(execute: controller.update)
        }

        final class Controller: UIViewController, UISheetPresentationControllerDelegate {
            var detents: [Detent]

            init(detents: [Detent]) {
                self.detents = detents
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                detents = []
                super.init(nibName: nil, bundle: nil)
            }

            func update() {
                let newDetents = detents.map(\.toPresentationDetents)

                if let controller = sheetPresentationController {
                    controller.detents = newDetents

                    // present as bottom sheet on compact-size (e.g landscape)
                    if #available(iOS 16.0, *) {
                        controller.prefersEdgeAttachedInCompactHeight = true
                        controller.widthFollowsPreferredContentSizeWhenEdgeAttached = true
                    } else {
                        // Getting some weird crash on iOS 15.5 when setting this to true. Disable for now
                        // This means that on iOS 15.0 landscape mode presentation will be full screen
                        controller.prefersEdgeAttachedInCompactHeight = false
                        controller.widthFollowsPreferredContentSizeWhenEdgeAttached = false
                    }
                    // scrolling with expand the bottom sheet if needed
                    controller.prefersScrollingExpandsWhenScrolledToEdge = true
                    // show drag indicator if bottom sheet is expandable
                    controller.prefersGrabberVisible = detents.count > 1
                    // always dim background
                    controller.presentingViewController.view?.tintAdjustmentMode = .dimmed
                }
            }

            override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
                super.viewWillTransition(to: size, with: coordinator)
                DispatchQueue.main.async(execute: update)
            }
        }
    }

#endif
