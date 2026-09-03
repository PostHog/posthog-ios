#if os(iOS) || os(macOS)
    import Foundation
    @testable import PostHog
    #if SWIFT_PACKAGE
        import PostHogTestsObjC
    #endif
    import Testing
    import UserNotifications
    #if os(iOS)
        import UIKit
    #endif

    private final class TestPushNotificationPublisher: PushNotificationPublishing {
        let onNotificationResponse = PostHogMulticastCallback<UNNotificationResponse>()
        let onDeviceToken = PostHogMulticastCallback<String>()
        private(set) var prewarmCount = 0
        private(set) var discardCount = 0
        private var isPrewarmed = false
        private var pendingResponse: UNNotificationResponse?

        func prewarmNotificationResponseCapture() {
            prewarmCount += 1
            isPrewarmed = true
        }

        func deliver(notificationResponse response: UNNotificationResponse) {
            guard onNotificationResponse.subscriberCount > 0 else {
                if isPrewarmed { pendingResponse = response }
                return
            }
            onNotificationResponse.invoke(response)
        }

        func consumePendingNotificationResponse() -> UNNotificationResponse? {
            defer { pendingResponse = nil }
            return pendingResponse
        }

        func discardPrewarmedNotificationResponseCapture() {
            discardCount += 1
            isPrewarmed = false
            pendingResponse = nil
        }
    }

    #if os(iOS)
        private final class ForwardedApplicationDelegate: NSObject, UIApplicationDelegate {
            var deviceToken: Data?
            var registrationError: Error?

            func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
                self.deviceToken = deviceToken
            }

            func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
                registrationError = error
            }
        }

        private final class ForwardingApplicationDelegate: NSObject, UIApplicationDelegate {
            let forwardedDelegate = ForwardedApplicationDelegate()

            override func forwardingTarget(for selector: Selector!) -> Any? {
                if selector == #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)) ||
                    selector == #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
                {
                    return forwardedDelegate
                }
                return nil
            }
        }
    #endif

    @Suite("Push Notification Swizzling Tests", .serialized)
    final class PostHogPushNotificationSwizzlingTest {
        private let publisher = TestPushNotificationPublisher()
        private let previousContainer: DI.Container

        init() {
            previousContainer = DI.main
            let container = DI.Container()
            container.pushNotificationPublisher = publisher
            DI.main = container
            // `PushNotificationPublisher.shared` is process-wide, so prewarm state leaks between tests.
            PushNotificationPublisher.reset()
        }

        deinit {
            PushNotificationPublisher.reset()
            DI.main = previousContainer
        }

        private var selector: Selector {
            #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
        }

        #if os(iOS)
            @Test("forwards app delegate callbacks to a UIApplicationDelegateAdaptor-style target")
            @MainActor
            func forwardsApplicationDelegateCallbacks() {
                let delegate = ForwardingApplicationDelegate()
                PushNotificationPublisher.shared.swizzleAppDelegateMethods(on: type(of: delegate))

                let appDelegate: UIApplicationDelegate = delegate
                let deviceToken = Data([0x01, 0x23, 0xFF])
                var capturedToken: String?
                let token = publisher.onDeviceToken.subscribe { capturedToken = $0 }
                appDelegate.application?(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

                let error = NSError(domain: "PostHogPushNotificationSwizzlingTest", code: 1)
                appDelegate.application?(UIApplication.shared, didFailToRegisterForRemoteNotificationsWithError: error)
                withExtendedLifetime(token) {}

                #expect(capturedToken == "0123ff")
                #expect(delegate.forwardedDelegate.deviceToken == deviceToken)
                #expect(delegate.forwardedDelegate.registrationError as? NSError == error)
            }
        #endif

        /// The placeholder stands in for a `UNNotificationResponse`, which has no public initializer.
        /// It is only ever compared by identity here — never dereferenced.
        private func withPlaceholderResponse(_ body: (UNNotificationResponse) -> Void) {
            let placeholder = NSObject()
            body(unsafeBitCast(placeholder, to: UNNotificationResponse.self))
            withExtendedLifetime(placeholder) {}
        }

        @Test("buffers a response delivered after prewarm but before any subscriber, and drains it once")
        func buffersResponseDeliveredBeforeSubscriber() {
            let publisher = PushNotificationPublisher.shared
            publisher.prewarmNotificationResponseCapture()

            withPlaceholderResponse { response in
                publisher.deliver(notificationResponse: response)

                #expect(publisher.consumePendingNotificationResponse() === response)
                #expect(publisher.consumePendingNotificationResponse() == nil)
            }
        }

        @Test("drops a response delivered with no subscriber when not prewarmed")
        func dropsResponseWhenNotPrewarmed() {
            let publisher = PushNotificationPublisher.shared

            withPlaceholderResponse { response in
                publisher.deliver(notificationResponse: response)
                #expect(publisher.consumePendingNotificationResponse() == nil)
            }
        }

        @Test("prewarming twice leaves the buffer window open exactly once")
        func prewarmIsIdempotent() {
            let publisher = PushNotificationPublisher.shared
            publisher.prewarmNotificationResponseCapture()
            publisher.prewarmNotificationResponseCapture()

            // Still buffering means the second call did not tear the prewarm window down.
            withPlaceholderResponse { response in
                publisher.deliver(notificationResponse: response)
                #expect(publisher.consumePendingNotificationResponse() === response)
            }
        }

        @Test("discarding a prewarm clears the buffer and ends the prewarm window")
        func discardEndsPrewarmWindow() {
            let publisher = PushNotificationPublisher.shared
            publisher.prewarmNotificationResponseCapture()

            withPlaceholderResponse { response in
                publisher.deliver(notificationResponse: response)
                publisher.discardPrewarmedNotificationResponseCapture()
                #expect(publisher.consumePendingNotificationResponse() == nil)

                publisher.deliver(notificationResponse: response)
                #expect(publisher.consumePendingNotificationResponse() == nil)
            }
        }

        @Test("prewarming while a subscriber is attached does not re-open the buffer window")
        func prewarmWithLiveSubscriberIsIgnored() {
            let publisher = PushNotificationPublisher.shared
            var token: RegistrationToken? = publisher.onNotificationResponse.subscribe { _ in }

            publisher.prewarmNotificationResponseCapture()
            token = nil

            withPlaceholderResponse { response in
                publisher.deliver(notificationResponse: response)
                #expect(publisher.consumePendingNotificationResponse() == nil)
            }
        }

        @Test("the public prewarm API reaches the publisher")
        @available(iOS 14.0, macOS 11.0, *)
        func publicPrewarmApiReachesPublisher() {
            #expect(publisher.prewarmCount == 0)
            PostHogSDK.prewarmPushNotificationOpenCapture()
            #expect(publisher.prewarmCount == 1)
        }

        /// Mirrors `PostHogIntegrationInstallationTest.getSut`, trimmed to what the discard gate reads.
        @available(iOS 14.0, macOS 11.0, *)
        private func makeSut(
            optOut: Bool = false,
            capturePushNotificationOpened: Bool = true,
            enableSwizzling: Bool = true
        ) -> PostHogSDK {
            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.errorTrackingConfig.autoCapture = false
            #if os(iOS)
                config.sessionReplay = false
            #endif
            config.optOut = optOut
            config.enableSwizzling = enableSwizzling
            config.capturePushNotificationOpened = capturePushNotificationOpened
            config.capturePushNotificationSubscriptions = false

            let storage = PostHogStorage(config)
            storage.reset()

            PostHogPushNotificationOpenIntegration.clearInstalls()
            return PostHogSDK.with(config)
        }

        @Test("setup() releases a prewarm when push-open capture is disabled")
        @available(iOS 14.0, macOS 11.0, *)
        func setupDiscardsPrewarmWhenCaptureDisabled() {
            let sut = makeSut(capturePushNotificationOpened: false)
            defer { sut.close() }

            #expect(publisher.discardCount == 1)
        }

        /// `setup()` skips `installIntegrations()` entirely while opted out, so the discard cannot
        /// live there without leaving an opted-out app swizzled for the process lifetime.
        @Test("setup() releases a prewarm while opted out, even with push-open capture enabled")
        @available(iOS 14.0, macOS 11.0, *)
        func setupDiscardsPrewarmWhileOptedOut() {
            let sut = makeSut(optOut: true, capturePushNotificationOpened: true)
            defer { sut.close() }

            #expect(publisher.discardCount == 1)
        }

        @Test("setup() with push-open capture enabled does not discard the prewarm")
        @available(iOS 14.0, macOS 11.0, *)
        func setupKeepsPrewarmWhenCaptureEnabled() {
            publisher.prewarmNotificationResponseCapture()

            let sut = makeSut(capturePushNotificationOpened: true)
            defer { sut.close() }

            #expect(publisher.discardCount == 0)
        }

        @Test("captures and calls an Objective-C delegate with the original selector")
        func callsObjectiveCDelegate() {
            let delegate = PHDirectNotificationDelegateTestFixture()
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(on: type(of: delegate))

            var captureCount = 0
            let token = publisher.onNotificationResponse.subscribe { _ in captureCount += 1 }
            var completionCount = 0
            delegate.invoke { completionCount += 1 }
            withExtendedLifetime(token) {}

            #expect(captureCount == 1)
            #expect(delegate.invocationCount == 1)
            #expect(delegate.receivedSelector == selector)
            #expect(completionCount == 1)
        }

        @Test("installing twice does not wrap the delegate twice")
        func duplicateInstallationIsHarmless() {
            let delegate = PHDuplicateNotificationDelegateTestFixture()
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(on: type(of: delegate))
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(on: type(of: delegate))

            var captureCount = 0
            let token = publisher.onNotificationResponse.subscribe { _ in captureCount += 1 }
            var completionCount = 0
            delegate.invoke { completionCount += 1 }
            withExtendedLifetime(token) {}

            #expect(captureCount == 1)
            #expect(delegate.invocationCount == 1)
            #expect(completionCount == 1)
        }

        @Test("completes when the Objective-C delegate omits the optional method")
        func missingImplementationCompletes() {
            let delegate = PHMissingNotificationDelegateTestFixture()
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(on: type(of: delegate))

            var captureCount = 0
            let token = publisher.onNotificationResponse.subscribe { _ in captureCount += 1 }
            var completionCount = 0
            delegate.invoke { completionCount += 1 }
            withExtendedLifetime(token) {}

            #expect(captureCount == 1)
            #expect(delegate.invocationCount == 0)
            #expect(completionCount == 1)
        }

        @Test("swizzling a subclass after its superclass does not wrap the inherited method twice")
        func superclassFirstDoesNotWrapInheritedMethodTwice() {
            let delegate = PHSuperclassFirstNotificationDelegateTestFixture()
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(
                on: PHSuperclassFirstNotificationDelegateBaseTestFixture.self
            )
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(on: type(of: delegate))

            var captureCount = 0
            let token = publisher.onNotificationResponse.subscribe { _ in captureCount += 1 }
            var completionCount = 0
            delegate.invoke { completionCount += 1 }
            withExtendedLifetime(token) {}

            #expect(captureCount == 1)
            #expect(delegate.invocationCount == 1)
            #expect(delegate.receivedSelector == selector)
            #expect(completionCount == 1)
        }

        @Test("swizzling an inherited implementation does not mutate its base class")
        func inheritedImplementationDoesNotMutateBaseClass() {
            let delegate = PHInheritedNotificationDelegateTestFixture()
            let baseDelegate = PHInheritedNotificationDelegateBaseTestFixture()
            PushNotificationPublisher.shared.swizzleNotificationDelegateMethods(on: type(of: delegate))

            var captureCount = 0
            let token = publisher.onNotificationResponse.subscribe { _ in captureCount += 1 }
            var delegateCompletionCount = 0
            delegate.invoke { delegateCompletionCount += 1 }
            var baseCompletionCount = 0
            baseDelegate.invoke { baseCompletionCount += 1 }
            withExtendedLifetime(token) {}

            #expect(captureCount == 1)
            #expect(delegate.invocationCount == 1)
            #expect(delegate.receivedSelector == selector)
            #expect(delegateCompletionCount == 1)
            #expect(baseDelegate.invocationCount == 1)
            #expect(baseDelegate.receivedSelector == selector)
            #expect(baseCompletionCount == 1)
        }
    }
#endif
