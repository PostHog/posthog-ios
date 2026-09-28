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

        /// The height the sheet's content needs, including the top safe area.
        let sheetHeight: CGFloat

        /// A sheet that fits in the window gets a detent of its own height; a taller one
        /// gets the medium and large detents so it can be expanded and scrolled.
        static func detents(forSheetHeight sheetHeight: CGFloat, availableHeight: CGFloat) -> [Detent] {
            if sheetHeight >= availableHeight {
                return [.medium, .large]
            }
            return [.height(sheetHeight)]
        }

        func makeUIViewController(context _: Context) -> Controller {
            Controller(sheetHeight: sheetHeight)
        }

        func updateUIViewController(_ controller: Controller, context _: Context) {
            controller.sheetHeight = sheetHeight
            DispatchQueue.main.async(execute: controller.update)
        }

        final class Controller: UIViewController, UISheetPresentationControllerDelegate {
            var sheetHeight: CGFloat

            init(sheetHeight: CGFloat) {
                self.sheetHeight = sheetHeight
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                sheetHeight = .zero
                super.init(nibName: nil, bundle: nil)
            }

            func update() {
                if let controller = sheetPresentationController {
                    // Measure against the window the sheet is shown in, not `UIScreen.main`, which
                    // can be a different display (e.g. a foldable's outer screen) or a different
                    // height than the window (e.g. Stage Manager).
                    let availableHeight = view.window?.bounds.height ?? controller.presentingViewController.view.bounds.height
                    let detents = SurveyPresentationDetentsRepresentable.detents(forSheetHeight: sheetHeight, availableHeight: availableHeight)
                    let newDetents = detents.map(\.toPresentationDetents)
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
