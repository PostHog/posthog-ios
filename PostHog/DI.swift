//
//  DI.swift
//  PostHog
//
//  Created by Yiannis Josephides on 17/12/2024.
//

// swiftlint:disable:next type_name
enum DI {
    static var main = Container()

    final class Container {
        // publishes global app lifecycle events
        lazy var appLifecyclePublisher: AppLifecyclePublishing = ApplicationLifecyclePublisher.shared
        // publishes global screen view events (UIViewController.viewDidAppear)
        lazy var screenViewPublisher: ScreenViewPublishing = ApplicationScreenViewPublisher.shared

        #if os(iOS) || os(tvOS) || os(macOS)
            // publishes global application events (UIApplication.sendEvent on iOS/tvOS, NSEvent monitor on macOS)
            lazy var applicationEventPublisher: ApplicationEventPublishing = ApplicationEventPublisher.shared
        #endif

        #if os(iOS) || os(macOS)
            // publishes global view layout events within a throttle interval (UIView.layoutSubviews on iOS, NSView.layout on macOS)
            lazy var viewLayoutPublisher: ViewLayoutPublishing = ApplicationViewLayoutPublisher.shared
        #endif
    }
}
