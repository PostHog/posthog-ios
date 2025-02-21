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
        // manages session rotation
        lazy var sessionManager: PostHogSessionManager = .init()
        // publishes global app lifecycle events
        lazy var appLifecyclePublisher: AppLifecyclePublishing = ApplicationLifecyclePublisher.shared
        // publishes global screen view events
        lazy var screenViewPublisher: ScreenViewPublishing = ApplicationScreenViewPublisher.shared
    }
}
