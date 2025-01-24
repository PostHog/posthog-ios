//
//  PostHogAppLifeCycleIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/02/2025.
//

import Foundation

/**
 Add capability to capture application lifecycle events.

 This integration:
 - captures an `App Installed` event on the first launch of the app
 - captures an `App Updated` event on any subsequent launch with a different version
 - captures an `App Opened` event when the app is opened (including the first launch)
 - captures an `App Backgrounded` event when the app moves to the background
 */
final class PostHogAppLifeCycleIntegration: PostHogIntegration {
    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false

    private weak var postHog: PostHogSDK?

    private var appFromBackground = false

    private var didBecomeActiveToken: RegistrationToken?
    private var didEnterBackgroundToken: RegistrationToken?
    private var didFinishLaunchingToken: RegistrationToken?
    private var didCaptureAppInstallOrUpdate = false

    func install(_ postHog: PostHogSDK) throws {
        try PostHogAppLifeCycleIntegration.integrationInstalledLock.withLock {
            if PostHogAppLifeCycleIntegration.integrationInstalled {
                throw InternalPostHogError(description: "App life cycle integration already installed to another PostHogSDK instance.")
            }
            PostHogAppLifeCycleIntegration.integrationInstalled = true
        }

        self.postHog = postHog

        start()
        captureAppInstallOrUpdated()
    }

    func uninstall(_ postHog: PostHogSDK) {
        // uninstall only for integration instance
        if self.postHog === postHog || self.postHog == nil {
            stop()
            self.postHog = nil
            PostHogAppLifeCycleIntegration.integrationInstalledLock.withLock {
                PostHogAppLifeCycleIntegration.integrationInstalled = false
            }
        }
    }

    /**
     Start capturing app lifecycles events
     */
    func start() {
        let publisher = DI.main.appLifecyclePublisher
        didFinishLaunchingToken = publisher.onDidFinishLaunching { [weak self] in
            self?.captureAppInstallOrUpdated()
        }
        didBecomeActiveToken = publisher.onDidBecomeActive { [weak self] in
            self?.captureAppOpened()
        }
        didEnterBackgroundToken = publisher.onDidEnterBackground { [weak self] in
            self?.captureAppBackgrounded()
        }
    }

    /**
     Stop capturing app lifecycle events
     */
    func stop() {
        didFinishLaunchingToken = nil
        didBecomeActiveToken = nil
        didEnterBackgroundToken = nil
    }

    private func captureAppInstallOrUpdated() {
        guard let postHog, !didCaptureAppInstallOrUpdate else { return }

        didCaptureAppInstallOrUpdate = true

        if !postHog.config.captureApplicationLifecycleEvents {
            hedgeLog("Skipping Application Installed/Application Updated event - captureApplicationLifecycleEvents is disabled in configuration")
            return
        }

        let bundle = Bundle.main

        let versionName = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionCode = bundle.infoDictionary?["CFBundleVersion"] as? String

        // capture app installed/updated
        let userDefaults = UserDefaults.standard

        let previousVersion = userDefaults.string(forKey: "PHGVersionKey")
        let previousVersionCode = userDefaults.string(forKey: "PHGBuildKeyV2")

        var props: [String: Any] = [:]
        var event: String
        if previousVersionCode == nil {
            // installed
            event = "Application Installed"
        } else {
            event = "Application Updated"

            // Do not send version updates if its the same
            if previousVersionCode == versionCode {
                return
            }

            if previousVersion != nil {
                props["previous_version"] = previousVersion
            }
            props["previous_build"] = previousVersionCode
        }

        var syncDefaults = false
        if versionName != nil {
            props["version"] = versionName
            userDefaults.setValue(versionName, forKey: "PHGVersionKey")
            syncDefaults = true
        }

        if versionCode != nil {
            props["build"] = versionCode
            userDefaults.setValue(versionCode, forKey: "PHGBuildKeyV2")
            syncDefaults = true
        }

        if syncDefaults {
            userDefaults.synchronize()
        }

        postHog.capture(event, properties: props)
    }

    private func captureAppOpened() {
        guard let postHog else { return }

        if !postHog.config.captureApplicationLifecycleEvents {
            hedgeLog("Skipping Application Opened event - captureApplicationLifecycleEvents is disabled in configuration")
            return
        }

        var props: [String: Any] = [:]
        props["from_background"] = appFromBackground

        if !appFromBackground {
            let bundle = Bundle.main

            let versionName = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            let versionCode = bundle.infoDictionary?["CFBundleVersion"] as? String

            if versionName != nil {
                props["version"] = versionName
            }
            if versionCode != nil {
                props["build"] = versionCode
            }

            appFromBackground = true
        }

        postHog.capture("Application Opened", properties: props)
    }

    private func captureAppBackgrounded() {
        guard let postHog else { return }

        if !postHog.config.captureApplicationLifecycleEvents {
            hedgeLog("Skipping Application Backgrounded event - captureApplicationLifecycleEvents is disabled in configuration")
            return
        }

        postHog.capture("Application Backgrounded")
    }
}

#if TESTING
    extension PostHogAppLifeCycleIntegration {
        static func clearInstalls() {
            integrationInstalledLock.withLock {
                integrationInstalled = false
            }
        }
    }
#endif
