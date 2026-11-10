//
//  PostHogAppLifeCycleIntegrationTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/02/2025.
//

import Foundation
@testable import PostHog
import Testing

#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

@Suite("Test App Lifecycle integration", .serialized)
final class PostHogAppLifeCycleIntegrationTest {
    var server: MockPostHogServer!
    let mockAppLifecycle: MockApplicationLifecyclePublisher

    init() {
        PostHogAppLifeCycleIntegration.clearInstalls()

        mockAppLifecycle = MockApplicationLifecyclePublisher()
        DI.main.appLifecyclePublisher = mockAppLifecycle

        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
        server = nil
        DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
    }

    private func getSut(
        flushAt: Int = 1,
        captureApplicationLifecycleEvents: Bool = true,
        disableFlushOnBackgroundForTesting: Bool = true,
        optOut: Bool = false
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9000")
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.optOut = optOut
        config.flushAt = flushAt
        config.maxBatchSize = flushAt
        config.disableFlushOnBackgroundForTesting = disableFlushOnBackgroundForTesting
        // Reachability now genuinely fires events queue callbacks (the events
        // queue used to be silently disconnected by the replay queue's
        // subscription). On a `.wifi` connection the queue auto-flushes shortly
        // after start, which is fine in production but causes lifecycle tests
        // to see an early single-event batch instead of the expected count.
        config.disableReachabilityForTesting = true

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    func setVersionDefaultsToCurrent() {
        let userDefaults = UserDefaults.standard
        let bundle = Bundle.main
        var synchronize = false
        let versionName = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionCode = bundle.infoDictionary?["CFBundleVersion"] as? String
        if let versionName {
            userDefaults.set(versionName, forKey: "PHGVersionKey")
            synchronize = true
        }
        if let versionCode {
            userDefaults.set(versionCode, forKey: "PHGBuildKeyV2")
            synchronize = true
        }

        if synchronize {
            userDefaults.synchronize()
        }
    }

    func setVersionDefaults(version: String? = nil, build: String? = nil) {
        let userDefaults = UserDefaults.standard

        if let version = version {
            userDefaults.set(version, forKey: "PHGVersionKey")
        } else {
            userDefaults.removeObject(forKey: "PHGVersionKey")
        }

        if let build = build {
            userDefaults.set(build, forKey: "PHGBuildKeyV2")
        } else {
            userDefaults.removeObject(forKey: "PHGBuildKeyV2")
        }

        userDefaults.synchronize()

        deleteSafely(applicationSupportDirectoryURL())
    }

    @Test("late setup or opt-in captures the first background and subsequent warm opens", arguments: [false, true])
    func capturesLifecycleAfterLateStart(optInAfterSetup: Bool) async throws {
        setVersionDefaults()
        mockAppLifecycle.isInBackground = false
        mockAppLifecycle.simulateAppDidFinishLaunching()
        mockAppLifecycle.simulateAppDidBecomeActive()

        let sut = getSut(flushAt: 100, optOut: optInAfterSetup)
        defer { sut.close() }
        if optInAfterSetup {
            sut.optIn()
        }

        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()
        mockAppLifecycle.simulateAppDidEnterBackground()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()
        mockAppLifecycle.simulateAppDidBecomeActive()
        sut.flush()

        let events = try await getServerEvents(server)
        #expect(events.map(\.event) == [
            "Application Installed",
            "Application Backgrounded",
            "Application Opened",
            "Application Backgrounded",
            "Application Opened",
        ])
        let opens = events.filter { $0.event == "Application Opened" }
        #expect(opens.map { $0.properties["from_background"] as? Bool } == [true, true])
    }

    @Test("setup or opt-in before first activation preserves cold launch", arguments: [false, true], [false, true])
    func preservesColdLaunch(startsInBackground: Bool, optInAfterSetup: Bool) async throws {
        setVersionDefaults()
        mockAppLifecycle.isInBackground = startsInBackground
        let sut = getSut(flushAt: 100, optOut: optInAfterSetup)
        defer { sut.close() }
        if optInAfterSetup {
            sut.optIn()
        }

        mockAppLifecycle.simulateAppDidFinishLaunching()
        if startsInBackground {
            mockAppLifecycle.simulateAppDidEnterBackground()
            mockAppLifecycle.simulateAppDidEnterBackground()
        }
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()
        mockAppLifecycle.simulateAppDidBecomeActive()
        sut.flush()

        let events = try await getServerEvents(server)
        #expect(events.map(\.event) == [
            "Application Installed",
            "Application Opened",
            "Application Backgrounded",
            "Application Opened",
        ])
        let opens = events.filter { $0.event == "Application Opened" }
        #expect(opens.map { $0.properties["from_background"] as? Bool } == [false, true])
    }

    @Test("worker startup samples current activity without losing a genuine cold open", arguments: [false, true], [false, true])
    @MainActor
    func capturesLifecycleAfterUnobservedWorkerStart(alreadyActive: Bool, optInAfterSetup: Bool) async throws {
        setVersionDefaults()
        mockAppLifecycle.isActive = alreadyActive
        let sut: PostHogSDK
        if optInAfterSetup {
            sut = getSut(flushAt: 100, optOut: true)
            let completed = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                sut.optIn()
                completed.signal()
            }
            // The worker must finish even while main cannot service its queued state check.
            #expect(completed.wait(timeout: .now() + 5) == .success)
        } else {
            sut = await Task.detached { self.getSut(flushAt: 100) }.value
        }
        defer { sut.close() }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        mockAppLifecycle.isActive = true
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.isActive = false
        mockAppLifecycle.isInBackground = true
        mockAppLifecycle.simulateAppDidEnterBackground()
        mockAppLifecycle.isInBackground = false
        mockAppLifecycle.isActive = true
        mockAppLifecycle.simulateAppDidBecomeActive()
        sut.flush()

        let events = try await getServerEvents(server)
        let coldOpen = alreadyActive ? [] : ["Application Opened"]
        #expect(events.map(\.event) == ["Application Installed"] + coldOpen + ["Application Backgrounded", "Application Opened"])
        let opens = events.filter { $0.event == "Application Opened" }
        let expectedFromBackground = alreadyActive ? [true] : [false, true]
        #expect(opens.map { $0.properties["from_background"] as? Bool } == expectedFromBackground)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
        private var lifecycleNotifications: (active: Notification.Name, background: Notification.Name) {
            #if os(macOS)
                return (NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification)
            #elseif os(visionOS)
                return (UIScene.didActivateNotification, UIScene.willDeactivateNotification)
            #else
                return (UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification)
            #endif
        }

        // Synthetic UIKit notifications do not change its live main-thread application state.
        #if os(macOS)
            private static let backgroundOptInThreads = [false, true]
        #else
            private static let backgroundOptInThreads = [true]
        #endif

        @Test("captures warm foreground after opting in while backgrounded", arguments: Self.backgroundOptInThreads)
        func capturesForegroundAfterBackgroundOptIn(optInOffMain: Bool) async throws {
            setVersionDefaults()
            let center = NotificationCenter()
            let publisher = ApplicationLifecyclePublisher(notificationCenter: center)
            DI.main.appLifecyclePublisher = publisher
            let sut = getSut(flushAt: 100, optOut: true)
            defer { sut.close() }

            center.post(name: lifecycleNotifications.active, object: nil)
            center.post(name: lifecycleNotifications.background, object: nil)
            if optInOffMain {
                await Task.detached { sut.optIn() }.value
            } else {
                await MainActor.run { sut.optIn() }
            }

            center.post(name: lifecycleNotifications.active, object: nil)
            center.post(name: lifecycleNotifications.active, object: nil)
            sut.capture("After foreground")
            sut.flush()

            let events = try await getServerEvents(server)
            #expect(events.map(\.event) == ["Application Installed", "Application Opened", "After foreground"])
            #expect(events.first { $0.event == "Application Opened" }?.properties["from_background"] as? Bool == true)
        }

        @Test("publisher remembers lifecycle state before notifying subscribers and across threads")
        func publisherRemembersLifecycleState() async {
            let center = NotificationCenter()
            let publisher = ApplicationLifecyclePublisher(notificationCenter: center)
            let initial = await Task.detached {
                (active: publisher.hasBecomeActive, background: publisher.isInBackground)
            }.value
            #expect(!initial.active)
            #expect(!initial.background)

            let activeToken = publisher.onDidBecomeActive.subscribe {
                #expect(publisher.hasBecomeActive)
                #expect(!publisher.isInBackground)
            }
            let backgroundToken = publisher.onDidEnterBackground.subscribe {
                #expect(publisher.hasBecomeActive)
                #expect(publisher.isInBackground)
            }
            let notifications = lifecycleNotifications
            let afterBackgrounding = await Task.detached {
                center.post(name: notifications.active, object: nil)
                center.post(name: notifications.background, object: nil)
                return (active: publisher.hasBecomeActive, background: publisher.isInBackground)
            }.value
            #expect(afterBackgrounding.active)
            #expect(afterBackgrounding.background)

            let afterForegrounding = await Task.detached {
                center.post(name: notifications.active, object: nil)
                return publisher.isInBackground
            }.value
            #expect(!afterForegrounding)
            withExtendedLifetime((activeToken, backgroundToken)) {}
        }
    #endif

    @Test("installs lifecycle integration even when event capture is disabled")
    func installsWithCaptureDisabled() {
        let config = PostHogConfig(projectToken: "test_project_token")
        config.captureApplicationLifecycleEvents = false
        #expect(config.getIntegrations().contains { $0 is PostHogAppLifeCycleIntegration })
    }

    @Test("a disabled client does not block lifecycle capture by an enabled client", arguments: [false, true])
    func disabledClientDoesNotBlockLifecycleCapture(previousInstall: Bool) async throws {
        setVersionDefaults(version: previousInstall ? "0.0.1" : nil, build: previousInstall ? "1" : nil)
        let disabled = getSut(captureApplicationLifecycleEvents: false)
        let enabled = getSut(flushAt: 4)
        defer { enabled.close() }

        disabled.close()

        mockAppLifecycle.simulateAppDidFinishLaunching()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()
        enabled.capture("Satisfy Queue")
        enabled.flush()

        let events = try await getServerEvents(server)
        #expect(events.map(\.event) == [
            previousInstall ? "Application Updated" : "Application Installed",
            "Application Opened",
            "Application Backgrounded",
            "Satisfy Queue",
        ])
        if previousInstall {
            #expect(events.first?.properties["previous_version"] as? String == "0.0.1")
            #expect(events.first?.properties["previous_build"] as? Int == 1)
        }

        let third = getSut(flushAt: 4)
        defer { third.close() }
        #expect(third.getAppLifeCycleIntegration() == nil)
    }

    #if targetEnvironment(simulator)
        @Test("disabled lifecycle capture remembers the current version", arguments: [false, true])
        func disabledCaptureRemembersVersion(previousInstall: Bool) async throws {
            setVersionDefaults(version: previousInstall ? "0.0.1" : nil, build: previousInstall ? "1" : nil)

            let sut = getSut(captureApplicationLifecycleEvents: false)
            defer { sut.close() }

            mockAppLifecycle.simulateAppDidFinishLaunching()
            mockAppLifecycle.simulateAppDidBecomeActive()
            mockAppLifecycle.simulateAppDidEnterBackground()
            sut.capture("Satisfy Queue")

            let events = try await getServerEvents(server)
            #expect(events.map(\.event) == ["Satisfy Queue"])
            let version = try #require(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            let build = try #require(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == version)
            #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") == build)
        }

        @Test("enabling lifecycle capture on a later launch does not fabricate an install")
        func enablingCaptureDoesNotFabricateInstall() async throws {
            setVersionDefaults()
            let first = getSut(captureApplicationLifecycleEvents: false)
            first.close()
            PostHogAppLifeCycleIntegration.clearInstalls()

            let second = getSut(flushAt: 2)
            defer { second.close() }
            mockAppLifecycle.simulateAppDidBecomeActive()
            second.capture("Satisfy Queue")

            let events = try await getServerEvents(server)
            #expect(events.map(\.event) == ["Application Opened", "Satisfy Queue"])
        }

        @Test("same build refreshes the saved version without an update event")
        func sameBuildRefreshesVersion() async throws {
            let build = try #require(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            setVersionDefaults(version: "0.0.1", build: build)
            let sut = getSut()
            defer { sut.close() }
            sut.capture("Satisfy Queue")

            let events = try await getServerEvents(server)
            #expect(events.map(\.event) == ["Satisfy Queue"])
            #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == appVersionString())
        }

        @Test("captures Application Installed event")
        func capturesApplicationInstalledEvent() async throws {
            // clear versions
            setVersionDefaults(version: nil, build: nil)

            // Ensure a "clean" install
            #if targetEnvironment(simulator)
                #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == nil)
                #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") == nil)
            #endif

            // SDK init
            let sut = getSut()

            // Simulate an app launch
            mockAppLifecycle.simulateAppDidFinishLaunching()

            let events = try await getServerEvents(server)

            // Verify Application Installed event
            #expect(events.count == 1)
            #expect(events.first?.event == "Application Installed")

            print("running tests")
            #expect(events.first?.properties["$app_version"] != nil)
            #expect(events.first?.properties["$app_build"] != nil)
            #expect(events.first?.properties["build"] != nil)
            #expect(events.first?.properties["$app_build_xcode"] as? String == Bundle.main.infoDictionary?["DTXcode"] as? String)

            #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") != nil)
            #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") != nil)

            sut.close()
        }

        @Test("captures Application Updated event")
        func capturesApplicationUpdatedEvent() async throws {
            // clear versions
            setVersionDefaults(version: "0.0.1", build: "1")

            // Ensure a "previous" install
            #if targetEnvironment(simulator)
                #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == "0.0.1")
                #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") == "1")
            #endif

            // SDK init
            let sut = getSut()

            // Simulate an app launch
            mockAppLifecycle.simulateAppDidFinishLaunching()

            let events = try await getServerEvents(server)

            // Verify Application Installed event
            #expect(events.count == 1)
            #expect(events.first?.event == "Application Updated")

            print("running tests")
            #expect(events.first?.properties["$app_version"] != nil)
            #expect(events.first?.properties["$app_build"] != nil)
            #expect(events.first?.properties["build"] != nil)
            #expect(events.first?.properties["previous_build"] != nil)
            #expect(events.first?.properties["$app_build_xcode"] as? String == Bundle.main.infoDictionary?["DTXcode"] as? String)

            #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") != nil)
            #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") != nil)

            sut.close()
        }

        @Test("captures Application Installed event when setup is delayed")
        func capturesDelayedApplicationInstalled() async throws {
            // clear versions
            setVersionDefaults(version: nil, build: nil)

            // Ensure a "clean" install
            #if targetEnvironment(simulator)
                #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == nil)
                #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") == nil)
            #endif

            // Simulate an app launch, before SDK is init
            mockAppLifecycle.simulateAppDidFinishLaunching()

            // SDK init after notification is fired
            let sut = getSut()

            let events = try await getServerEvents(server)

            // Verify Application Installed event
            #expect(events.count == 1)
            #expect(events.first?.event == "Application Installed")

            print("running tests")
            #expect(events.first?.properties["$app_version"] != nil)
            #expect(events.first?.properties["$app_build"] != nil)
            #expect(events.first?.properties["build"] != nil)

            #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") != nil)
            #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") != nil)

            sut.close()
        }

        @Test("captures Application Installed event once")
        func capturesApplicationInstalledEventOnce() async throws {
            // clear versions
            setVersionDefaults(version: nil, build: nil)

            // Ensure a "clean" install
            #if targetEnvironment(simulator)
                #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == nil)
                #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") == nil)
            #endif

            // SDK init
            let sut = getSut(flushAt: 4)

            // Simulate app life cycle events
            Task { @MainActor in
                mockAppLifecycle.simulateAppDidFinishLaunching()
                Task { @MainActor in
                    mockAppLifecycle.simulateAppDidBecomeActive()
                    Task { @MainActor in
                        mockAppLifecycle.simulateAppDidEnterBackground()
                        Task { @MainActor in
                            mockAppLifecycle.simulateAppDidFinishLaunching()
                            Task { @MainActor in
                                mockAppLifecycle.simulateAppDidBecomeActive()
                            }
                        }
                    }
                }
            }

            let events = try await getServerEvents(server)

            // Verify Application Installed event
            #expect(events.count == 4)
            #expect(events[0].event == "Application Installed")
            #expect(events[1].event == "Application Opened")
            #expect(events[2].event == "Application Backgrounded") // <-- note missing second Application Installed
            #expect(events[3].event == "Application Opened")

            sut.close()
        }

    #endif

    @Test("captures Application Opened event")
    func capturesApplicationOpenedEvent() async throws {
        setVersionDefaults(version: nil, build: nil)

        // SDK init
        let sut = getSut(flushAt: 2)

        // Simulate an app open
        mockAppLifecycle.simulateAppDidFinishLaunching()
        mockAppLifecycle.simulateAppDidBecomeActive()

        let events = try await getServerEvents(server)

        // Verify Application Installed event
        #expect(events.count == 2)
        #expect(events[1].event == "Application Opened")
        #expect(events[1].properties["from_background"] as? Bool == false)

        #if targetEnvironment(simulator)
            #expect(events[1].properties["version"] != nil)
            #expect(events[1].properties["build"] != nil)
            #expect(events[1].properties["$app_build"] != nil)
        #endif

        sut.close()
    }

    @Test("captures Application Backgrounded event")
    func capturesApplicationBackgroundedEvent() async throws {
        setVersionDefaults(version: nil, build: nil)
        // SDK init
        let sut = getSut(flushAt: 3)

        // Simulate an app backgrounded
        mockAppLifecycle.simulateAppDidFinishLaunching()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()

        let events = try await getServerEvents(server)

        // Verify Application Installed event
        #expect(events.count == 3)
        #expect(events[2].event == "Application Backgrounded")

        sut.close()
    }

    @Test("respects configuration and does not emit any events")
    func respectsConfigurationAndDoesNotEmitEvents() async throws {
        // clear versions
        setVersionDefaults(version: nil, build: nil)

        // Ensure a "clean" install
        #if targetEnvironment(simulator)
            #expect(UserDefaults.standard.string(forKey: "PHGVersionKey") == nil)
            #expect(UserDefaults.standard.string(forKey: "PHGBuildKeyV2") == nil)
        #endif

        // SDK init
        let sut = getSut(flushAt: 1, captureApplicationLifecycleEvents: false)

        // Simulate app life cycle events
        mockAppLifecycle.simulateAppDidFinishLaunching()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()

        sut.capture("Satisfy Queue 1")

        let events = try await getServerEvents(server)

        // Verify Application Installed event
        #expect(events.count == 1)
        #expect(events[0].event == "Satisfy Queue 1")

        sut.close()
    }

    @Test("captures Application Opened event from background should be true")
    func capturesApplicationOpenedEventFromBackgroundTrue() async throws {
        setVersionDefaults(version: nil, build: nil)

        // SDK init
        let sut = getSut(flushAt: 4)

        // Simulate an app open
        mockAppLifecycle.simulateAppDidFinishLaunching()
        mockAppLifecycle.simulateAppDidBecomeActive()
        mockAppLifecycle.simulateAppDidEnterBackground()
        mockAppLifecycle.simulateAppDidBecomeActive()

        let events = try await getServerEvents(server)

        // Verify Application Installed event
        #expect(events.count == 4)
        #expect(events[3].event == "Application Opened")
        #expect(events[3].properties["from_background"] as? Bool == true)

        #if targetEnvironment(simulator)
            #expect(events[1].properties["version"] != nil)
            #expect(events[1].properties["build"] != nil)
            #expect(events[1].properties["$app_build"] != nil)
        #endif

        sut.close()
    }

    @Test("should not captures two consecutive Application Backgrounded events")
    func doesNotCaptureConsecutiveApplicationBackgroundedEvents() async throws {
        setVersionDefaults(version: nil, build: nil)

        // SDK init
        let sut = getSut(flushAt: 6)

        // Simulate an app open
        mockAppLifecycle.simulateAppDidFinishLaunching() // installed
        mockAppLifecycle.simulateAppDidBecomeActive() // opened
        mockAppLifecycle.simulateAppDidEnterBackground() // backgrounded
        mockAppLifecycle.simulateAppDidBecomeActive() // opened
        mockAppLifecycle.simulateAppDidEnterBackground() // backgrounded

        // Simulate app launched in background
        mockAppLifecycle.simulateAppDidFinishLaunching() // launched in background
        mockAppLifecycle.simulateAppDidEnterBackground()

        sut.capture("Satisfy Queue")

        let events = try await getServerEvents(server)

        let expectedEventNames = [
            "Application Installed",
            "Application Opened",
            "Application Backgrounded",
            "Application Opened",
            "Application Backgrounded",
            "Satisfy Queue",
        ]

        #expect(events.map(\.event) == expectedEventNames)

        sut.close()
    }

    @Test("flushes the queue when the app enters background")
    func flushesQueueOnBackground() async throws {
        setVersionDefaults(version: nil, build: nil)

        // SDK init with flush-on-background enabled and high flushAt so events are not auto-flushed
        let sut = getSut(
            flushAt: 100,
            captureApplicationLifecycleEvents: false,
            disableFlushOnBackgroundForTesting: false
        )

        // Capture some events
        sut.capture("event 1")
        sut.capture("event 2")

        // Simulate background - this should trigger a flush
        mockAppLifecycle.simulateAppDidEnterBackground()

        let events = try await getServerEvents(server)

        #expect(events.count == 2)
        #expect(events[0].event == "event 1")
        #expect(events[1].event == "event 2")

        sut.close()
    }
}
