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
        lazy var appLifecyclePublisher: AppLifecyclePublishing = ApplicationLifecyclePublisher.shared
        lazy var sessionManager: PostHogSessionManager = .init()
    }
}
