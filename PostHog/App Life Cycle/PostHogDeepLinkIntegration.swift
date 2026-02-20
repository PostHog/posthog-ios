//
//  PostHogDeepLinkIntegration.swift
//  PostHog
//
//  Created by Jeremiah Erinola on 18.02.26.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#endif

class PostHogDeepLinkIntegration: NSObject, PostHogIntegration {
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
        let swizzledOpenURLSelector = #selector(NSObject.ph_swizzled_application(_:open:options:))

        // Add the swizzled implementation to the delegate class
        let openURLMethod = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_swizzled_application(_:open:options:)))
        if let method = openURLMethod {
            addMethod(forClass: delegateClass, selector: swizzledOpenURLSelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
        }

        // Check if the delegate implements the original method, if not add a fallback
        if class_getInstanceMethod(delegateClass, openURLSelector) == nil {
            let method = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_fallback_application(_:open:options:)))
            if let method = method {
                addMethod(forClass: delegateClass, selector: openURLSelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
            }
        }

        swizzle(
            forClass: delegateClass,
            original: openURLSelector,
            new: swizzledOpenURLSelector
        )

        // application(_:continue:restorationHandler:)
        let continueActivitySelector = #selector(UIApplicationDelegate.application(_:continue:restorationHandler:))
        let swizzledContinueActivitySelector = #selector(NSObject.ph_swizzled_application(_:continue:restorationHandler:))

        // Add the swizzled implementation to the delegate class
        let continueActivityMethod = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_swizzled_application(_:continue:restorationHandler:)))
        if let method = continueActivityMethod {
            addMethod(forClass: delegateClass, selector: swizzledContinueActivitySelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
        }

        if class_getInstanceMethod(delegateClass, continueActivitySelector) == nil {
            let method = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_fallback_application(_:continue:restorationHandler:)))
            if let method = method {
                addMethod(forClass: delegateClass, selector: continueActivitySelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
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
        let swizzledOpenURLContextsSelector = #selector(NSObject.ph_swizzled_scene(_:openURLContexts:))

        // Add the swizzled implementation to the delegate class
        let openURLContextsMethod = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_swizzled_scene(_:openURLContexts:)))
        if let method = openURLContextsMethod {
            addMethod(forClass: delegateClass, selector: swizzledOpenURLContextsSelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
        }

        if class_getInstanceMethod(delegateClass, openURLContextsSelector) == nil {
             let method = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_fallback_scene(_:openURLContexts:)))
             if let method = method {
                 addMethod(forClass: delegateClass, selector: openURLContextsSelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
             }
         }

        swizzle(
            forClass: delegateClass,
            original: openURLContextsSelector,
            new: swizzledOpenURLContextsSelector
        )

        // scene(_:continue:)
        let continueActivitySelector = #selector(UISceneDelegate.scene(_:continue:))
        let swizzledContinueActivitySelector = #selector(NSObject.ph_swizzled_scene(_:continue:))

        // Add the swizzled implementation to the delegate class
        let continueActivityMethod = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_swizzled_scene(_:continue:)))
        if let method = continueActivityMethod {
            addMethod(forClass: delegateClass, selector: swizzledContinueActivitySelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
        }

        if class_getInstanceMethod(delegateClass, continueActivitySelector) == nil {
             let method = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_fallback_scene(_:continue:)))
             if let method = method {
                 addMethod(forClass: delegateClass, selector: continueActivitySelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
             }
         }

        swizzle(
            forClass: delegateClass,
            original: continueActivitySelector,
            new: swizzledContinueActivitySelector
        )

        // scene(_:willConnectTo:options:)
        // Only swizzle if the delegate implements it, to avoid breaking default Storyboard behavior
        let willConnectSelector = #selector(UISceneDelegate.scene(_:willConnectTo:options:))
        let swizzledWillConnectSelector = #selector(NSObject.ph_swizzled_scene(_:willConnectTo:options:))

        if class_getInstanceMethod(delegateClass, willConnectSelector) != nil {
            let willConnectMethod = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_swizzled_scene(_:willConnectTo:options:)))

            if let method = willConnectMethod {
                addMethod(forClass: delegateClass, selector: swizzledWillConnectSelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
            }

            // Fallback is theoretically needed if we exchange, but here we ONLY swizzle if method exists.
            // However, to be consistent and safe if logic changes:
             if class_getInstanceMethod(delegateClass, willConnectSelector) == nil {
                 let method = class_getInstanceMethod(NSObject.self, #selector(NSObject.ph_fallback_scene(_:willConnectTo:options:)))
                 if let method = method {
                     addMethod(forClass: delegateClass, selector: willConnectSelector, implementation: method_getImplementation(method), types: String(cString: method_getTypeEncoding(method)!))
                 }
             }

            swizzle(
                forClass: delegateClass,
                original: willConnectSelector,
                new: swizzledWillConnectSelector
            )
        }
    }

    @objc private func sceneWillConnect(_ notification: Notification) {
        if #available(iOS 13.0, tvOS 13.0, *) {
            guard let scene = notification.object as? UIScene,
                  let delegate = scene.delegate else { return }
            swizzleUISceneDelegate(delegate)
        }
    }

    #endif
}

extension NSObject {
    #if os(iOS) || os(tvOS)
    // MARK: - Swizzled Implementations (to be added to delegate classes)

    @objc func ph_swizzled_application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        PostHogDeepLinkIntegration.trackDeepLink(url: url, options: options)
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

    @available(iOS 13.0, tvOS 13.0, *)
    @objc func ph_swizzled_scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        for context in connectionOptions.urlContexts {
            PostHogDeepLinkIntegration.trackDeepLink(url: context.url, options: context.options)
        }
        for userActivity in connectionOptions.userActivities {
            PostHogDeepLinkIntegration.trackDeepLink(userActivity: userActivity)
        }
        ph_forward_sceneWillConnect(scene, session, connectionOptions)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @inline(never)
    private func ph_forward_sceneWillConnect(_ scene: UIScene, _ session: UISceneSession, _ options: UIScene.ConnectionOptions) {
        ph_swizzled_scene(scene, willConnectTo: session, options: options)
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

    @available(iOS 13.0, tvOS 13.0, *)
    @objc func ph_fallback_scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
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

    /// Builds the properties dictionary for a deep link event.
    /// Extracted for unit testing of property extraction logic.
    /// - Parameters:
    ///   - url: The deep link URL opened.
    ///   - referrer: The referrer string (may be a URL or other identifier).
    /// - Returns: A dictionary of event properties including `url`, optional `$referrer` and `$referring_domain`.
    static func buildDeepLinkProperties(url: URL, referrer: String?) -> [String: Any] {
        var properties: [String: Any] = ["url": url.absoluteString]

        if let referrer = referrer {
            properties["$referrer"] = referrer

            // Try to extract domain from referrer if it looks like a URL
            if let referrerURL = URL(string: referrer), let host = referrerURL.host {
                properties["$referring_domain"] = host
            }
        }

        return properties
    }

    static func trackDeepLink(url: URL, referrer: String?) {
        guard let postHog = PostHogDeepLinkIntegration.currentInstance,
              postHog.config.captureDeepLinks else { return }

        let properties = buildDeepLinkProperties(url: url, referrer: referrer)
        postHog.capture("Deep Link Opened", properties: properties)
    }
}

