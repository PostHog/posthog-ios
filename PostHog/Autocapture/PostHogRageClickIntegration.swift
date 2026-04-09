//
//  PostHogRageClickIntegration.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/04/2026.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    final class PostHogRageClickIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private weak var postHog: PostHogSDK?
        private var rageClickDetector: RageClickDetector?
        private var applicationEventToken: RegistrationToken?

        func install(_ postHog: PostHogSDK) throws {
            try PostHogRageClickIntegration.integrationInstalledLock.withLock {
                if PostHogRageClickIntegration.integrationInstalled {
                    throw InternalPostHogError(description: "Rage click integration already installed to another PostHogSDK instance.")
                }
                PostHogRageClickIntegration.integrationInstalled = true
            }

            self.postHog = postHog
            rageClickDetector = RageClickDetector(config: postHog.config.rageClickConfig)

            start()
        }

        func uninstall(_ postHog: PostHogSDK) {
            // uninstall only for integration instance
            if self.postHog === postHog || self.postHog == nil {
                stop()
                self.postHog = nil
                PostHogRageClickIntegration.integrationInstalledLock.withLock {
                    PostHogRageClickIntegration.integrationInstalled = false
                }
            }
        }

        func start() {
            let applicationEventPublisher = DI.main.applicationEventPublisher
            applicationEventToken = applicationEventPublisher.onApplicationEvent.subscribe { [weak self] event, _ in
                self?.handleApplicationEvent(event)
            }
        }

        func stop() {
            applicationEventToken = nil
        }

        private func handleApplicationEvent(_ event: UIEvent) {
            guard postHog?.isRageClickActive() == true else {
                return
            }

            guard event.type == .touches,
                  let window = UIApplication.getCurrentWindow(),
                  let touches = event.touches(for: window)
            else {
                return
            }

            // Rage clicks represent repeated single-pointer frustration taps.
            // Ignore multi-touch interactions (e.g. pinch/zoom) to avoid false positives.
            guard touches.count == 1,
                  let touch = touches.first,
                  touch.phase == .ended,
                  touch.tapCount > 0
            else {
                return
            }

            captureRageClickIfNeeded(
                touchCoordinates: touch.location(in: window),
                screenName: currentScreenName(),
                elementsChain: ""
            )
        }

        private func captureRageClickIfNeeded(
            touchCoordinates: CGPoint,
            screenName: String?,
            elementsChain: String
        ) {
            guard let postHog,
                  let rageClickDetector,
                  rageClickDetector.isRageClick(
                      x: touchCoordinates.x,
                      y: touchCoordinates.y,
                      timestamp: ProcessInfo.processInfo.systemUptime
                  )
            else {
                return
            }

            var properties: [String: Any] = [
                "$touch_x": touchCoordinates.x,
                "$touch_y": touchCoordinates.y,
            ]

            if let screenName {
                properties["$screen_name"] = screenName
            }

            postHog.autocapture(
                eventName: "$rageclick",
                eventType: EventType.kTouch,
                elementsChain: elementsChain,
                properties: properties
            )
        }

        private func currentScreenName() -> String? {
            guard let controller = UIViewController.ph_topViewController() else {
                return nil
            }
            return UIViewController.getViewControllerName(controller)
        }
    }

    #if TESTING
        extension PostHogRageClickIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
            }

            func processTapForTesting(
                x: CGFloat,
                y: CGFloat,
                screenName: String? = "TestScreen",
                elementsChain: String = ""
            ) {
                captureRageClickIfNeeded(
                    touchCoordinates: CGPoint(x: x, y: y),
                    screenName: screenName,
                    elementsChain: elementsChain
                )
            }
        }
    #endif
#endif
