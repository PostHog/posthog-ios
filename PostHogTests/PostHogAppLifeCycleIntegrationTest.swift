//
//  PostHogAppLifeCycleIntegrationTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/02/2025.
//

import Foundation
import Testing

@testable import PostHog

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
        captureApplicationLifecycleEvents: Bool = true
    ) -> PostHogSDK {
        let config = PostHogConfig(apiKey: "app_lifecycle", host: "http://localhost:9000")
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.flushAt = flushAt
        config.maxBatchSize = flushAt

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

    #if targetEnvironment(simulator)
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
            #expect(events.first?.properties["build"] != nil)
            #expect(events.first?.properties["build"] != nil)

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
            #expect(events.first?.properties["build"] != nil)
            #expect(events.first?.properties["build"] != nil)

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
            #expect(events.first?.properties["build"] != nil)
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
}
