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
        }

        deinit {
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
