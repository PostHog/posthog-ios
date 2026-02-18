//
//  PostHogDeepLinkIntegration.swift
//  PostHog
//
//  Created by PostHog on 27.02.25.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#endif

class PostHogDeepLinkIntegration: PostHogIntegration {
    var requiresSwizzling: Bool { true }

    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false
    private static var swizzledClasses = Set<String>()

    private weak var postHog: PostHogSDK?

    // Store a reference to the active SDK instance for the static tracking methods
    // We only support one active SDK instance for deep link tracking at a time because
    // deep links are global app events.
    private static weak var currentInstance: PostHogSDK?

    func install(_ postHog: PostHogSDK) throws {
        try PostHogDeepLinkIntegration.integrationInstalledLock.withLock {
            if PostHogDeepLinkIntegration.integrationInstalled {
                throw InternalPostHogError(description: "Deep link integration already installed to another PostHogSDK instance.")
            }
            PostHogDeepLinkIntegration.integrationInstalled = true
        }

        self.postHog = postHog
        PostHogDeepLinkIntegration.currentInstance = postHog

        start()
    }

    func uninstall(_ postHog: PostHogSDK) {
        if self.postHog === postHog || self.postHog == nil {
            stop()
            self.postHog = nil
            PostHogDeepLinkIntegration.currentInstance = nil
            PostHogDeepLinkIntegration.integrationInstalledLock.withLock {
                PostHogDeepLinkIntegration.integrationInstalled = false
            }
        }
    }

    func start() {
        #if os(iOS) || os(tvOS)
        // Swizzle UIApplicationDelegate
        if let delegate = UIApplication.shared.delegate {
            swizzleUIApplicationDelegate(delegate)
        }

        // Swizzle connected scenes
        if #available(iOS 13.0, tvOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let delegate = scene.delegate {
                    swizzleUISceneDelegate(delegate)
                }
            }

            // Observe new scenes connecting
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(sceneWillConnect(_:)),
                                                   name: UIScene.willConnectNotification,
                                                   object: nil)
        }
        #endif
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    #if os(iOS) || os(tvOS)
    private func swizzleUIApplicationDelegate(_ delegate: UIApplicationDelegate) {
        let delegateClass: AnyClass = type(of: delegate)
        let className = String(describing: delegateClass)

        // Ensure we only swizzle each class once
        var alreadySwizzled = false
        PostHogDeepLinkIntegration.integrationInstalledLock.withLock {
            if PostHogDeepLinkIntegration.swizzledClasses.contains(className) {
                alreadySwizzled = true
            } else {
                PostHogDeepLinkIntegration.swizzledClasses.insert(className)
            }
        }

        if alreadySwizzled { return }

        // application(_:open:options:)
        let openURLSelector = #selector(UIApplicationDelegate.application(_:open:options:))
        let swizzledOpenURLSelector = #selector(UIApplicationDelegate.ph_swizzled_application(_:open:options:))

        // Add the swizzled implementation to the delegate class
        let openURLMethod = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_swizzled_application(_:open:options:)))
        if let method = openURLMethod {
            addMethod(forClass: delegateClass, selector: swizzledOpenURLSelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
        }

        // Check if the delegate implements the original method, if not add a fallback
        if class_getInstanceMethod(delegateClass, openURLSelector) == nil {
            let method = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_fallback_application(_:open:options:)))
            if let method = method {
                addMethod(forClass: delegateClass, selector: openURLSelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
            }
        }

        swizzle(
            forClass: delegateClass,
            original: openURLSelector,
            new: swizzledOpenURLSelector
        )

        // application(_:continue:restorationHandler:)
        let continueActivitySelector = #selector(UIApplicationDelegate.application(_:continue:restorationHandler:))
        let swizzledContinueActivitySelector = #selector(UIApplicationDelegate.ph_swizzled_application(_:continue:restorationHandler:))

        // Add the swizzled implementation to the delegate class
        let continueActivityMethod = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_swizzled_application(_:continue:restorationHandler:)))
        if let method = continueActivityMethod {
            addMethod(forClass: delegateClass, selector: swizzledContinueActivitySelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
        }

        if class_getInstanceMethod(delegateClass, continueActivitySelector) == nil {
            let method = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_fallback_application(_:continue:restorationHandler:)))
            if let method = method {
                addMethod(forClass: delegateClass, selector: continueActivitySelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
            }
        }

        swizzle(
            forClass: delegateClass,
            original: continueActivitySelector,
            new: swizzledContinueActivitySelector
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func swizzleUISceneDelegate(_ delegate: UISceneDelegate) {
        let delegateClass: AnyClass = type(of: delegate)
        let className = String(describing: delegateClass)

        // Ensure we only swizzle each class once
        var alreadySwizzled = false
        PostHogDeepLinkIntegration.integrationInstalledLock.withLock {
            if PostHogDeepLinkIntegration.swizzledClasses.contains(className) {
                alreadySwizzled = true
            } else {
                PostHogDeepLinkIntegration.swizzledClasses.insert(className)
            }
        }

        if alreadySwizzled { return }

        // scene(_:openURLContexts:)
        let openURLContextsSelector = #selector(UISceneDelegate.scene(_:openURLContexts:))
        let swizzledOpenURLContextsSelector = #selector(UISceneDelegate.ph_swizzled_scene(_:openURLContexts:))

        // Add the swizzled implementation to the delegate class
        let openURLContextsMethod = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_swizzled_scene(_:openURLContexts:)))
        if let method = openURLContextsMethod {
            addMethod(forClass: delegateClass, selector: swizzledOpenURLContextsSelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
        }

        if class_getInstanceMethod(delegateClass, openURLContextsSelector) == nil {
             let method = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_fallback_scene(_:openURLContexts:)))
             if let method = method {
                 addMethod(forClass: delegateClass, selector: openURLContextsSelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
             }
         }

        swizzle(
            forClass: delegateClass,
            original: openURLContextsSelector,
            new: swizzledOpenURLContextsSelector
        )

        // scene(_:continue:)
        let continueActivitySelector = #selector(UISceneDelegate.scene(_:continue:))
        let swizzledContinueActivitySelector = #selector(UISceneDelegate.ph_swizzled_scene(_:continue:))

        // Add the swizzled implementation to the delegate class
        let continueActivityMethod = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_swizzled_scene(_:continue:)))
        if let method = continueActivityMethod {
            addMethod(forClass: delegateClass, selector: swizzledContinueActivitySelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
        }

        if class_getInstanceMethod(delegateClass, continueActivitySelector) == nil {
             let method = class_getInstanceMethod(PostHogDeepLinkIntegration.self, #selector(PostHogDeepLinkIntegration.ph_fallback_scene(_:continue:)))
             if let method = method {
                 addMethod(forClass: delegateClass, selector: continueActivitySelector, implementation: method_getImplementation(method), types: method_getTypeEncoding(method)!)
             }
         }

        swizzle(
            forClass: delegateClass,
            original: continueActivitySelector,
            new: swizzledContinueActivitySelector
        )
    }

    @objc private func sceneWillConnect(_ notification: Notification) {
        if #available(iOS 13.0, tvOS 13.0, *) {
            guard let scene = notification.object as? UIScene,
                  let delegate = scene.delegate else { return }
            swizzleUISceneDelegate(delegate)
        }
    }

    // MARK: - Swizzled Implementations (to be added to delegate classes)

    @objc func ph_swizzled_application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        PostHogDeepLinkIntegration.trackDeepLink(url: url, options: options)
        // Call the original implementation (which is now swizzled to this method, but the selector points to the original implementation due to the exchange)
        // However, since we are adding this method to the delegate class, 'self' will be the delegate instance.
        // The original selector now points to this implementation.
        // The swizzled selector points to the original implementation.
        // So we need to call the method corresponding to the swizzled selector on self.

        // Wait, standard swizzling:
        // original -> originalImp
        // swizzled -> swizzledImp
        // exchange:
        // original -> swizzledImp
        // swizzled -> originalImp

        // Inside swizzledImp (this function):
        // calling self.swizzled() calls originalImp.

        return ph_swizzled_application(app, open: url, options: options)
    }

    @objc func ph_swizzled_application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        PostHogDeepLinkIntegration.trackDeepLink(userActivity: userActivity)
        return ph_swizzled_application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @objc func ph_swizzled_scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            PostHogDeepLinkIntegration.trackDeepLink(url: context.url, options: context.options)
        }
        ph_swizzled_scene(scene, openURLContexts: URLContexts)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @objc func ph_swizzled_scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        PostHogDeepLinkIntegration.trackDeepLink(userActivity: userActivity)
        ph_swizzled_scene(scene, continue: userActivity)
    }

    // MARK: - Fallback implementations for adding methods

    @objc func ph_fallback_application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return false
    }

    @objc func ph_fallback_application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return false
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @objc func ph_fallback_scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @objc func ph_fallback_scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    }
    #endif
}

// MARK: - Tracking Logic

extension PostHogDeepLinkIntegration {
    #if os(iOS) || os(tvOS)
    static func trackDeepLink(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        let referrer = options[.sourceApplication] as? String
        trackDeepLink(url: url, referrer: referrer)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    static func trackDeepLink(url: URL, options: UIScene.OpenURLOptions) {
        trackDeepLink(url: url, referrer: options.sourceApplication)
    }

    static func trackDeepLink(userActivity: NSUserActivity) {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            trackDeepLink(url: url, referrer: userActivity.referrerURL?.absoluteString)
        }
    }
    #endif

    static func trackDeepLink(url: URL, referrer: String?) {
        guard let postHog = PostHogDeepLinkIntegration.currentInstance,
              postHog.config.captureDeepLinks else { return }

        var properties: [String: Any] = ["url": url.absoluteString]

        if let referrer = referrer {
            properties["$referrer"] = referrer

            // Try to extract domain from referrer if it looks like a URL
            if let referrerURL = URL(string: referrer), let host = referrerURL.host {
                properties["$referring_domain"] = host
            }
        }

        postHog.capture("Deep Link Opened", properties: properties)
    }
}
