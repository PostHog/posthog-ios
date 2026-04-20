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

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            let didInstall = PostHogRageClickIntegration.integrationInstalledLock.withLock {
                if PostHogRageClickIntegration.integrationInstalled {
                    return false
                }
                PostHogRageClickIntegration.integrationInstalled = true
                return true
            }

            guard didInstall else {
                return .skipped(.alreadyInstalled)
            }

            self.postHog = postHog
            rageClickDetector = RageClickDetector(config: postHog.config.rageClickConfig)

            start()
            return .installed
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
                  let touches = event.allTouches
            else {
                return
            }

            // Rage clicks represent repeated single-pointer frustration taps.
            // Ignore multi-touch interactions (e.g. pinch/zoom) to avoid false positives.
            guard touches.count == 1,
                  let touch = touches.first,
                  let window = touch.window,
                  touch.phase == .ended,
                  touch.tapCount > 0
            else {
                return
            }

            let touchCoordinates = touch.location(in: window)
            let eventData = touch.view?.eventData(touchCoordinates: touchCoordinates)
            let elementsChain = eventData?.getElementChain() ?? ""

            captureRageClickIfNeeded(
                touchCoordinates: touchCoordinates,
                screenName: eventData?.screenName ?? currentScreenName(),
                elementsChain: elementsChain,
                eventData: eventData
            )
        }

        private func captureRageClickIfNeeded(
            touchCoordinates: CGPoint,
            screenName: String?,
            elementsChain: String,
            eventData: PostHogAutocaptureEventTracker.EventData?
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

            let normalizedScreenName = screenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedElementsChain = elementsChain.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasScreenName = normalizedScreenName?.isEmpty == false
            let hasElementId = eventData?.viewHierarchy.contains { $0.label?.isEmpty == false } ?? false

            // Keep rage clicks only when they contain enough context to be actionable:
            // - screen name is sufficient context when paired with touch coordinates
            // - without screen name: require a concrete element id
            guard hasScreenName || hasElementId else {
                return
            }

            var properties: [String: Any] = [
                "$touch_x": touchCoordinates.x,
                "$touch_y": touchCoordinates.y,
            ]

            if let normalizedScreenName, !normalizedScreenName.isEmpty {
                properties["$screen_name"] = normalizedScreenName
            }

            postHog.rageclick(
                eventType: EventType.kTouch,
                elementsChain: normalizedElementsChain,
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
                touchX: CGFloat,
                touchY: CGFloat,
                screenName: String? = "TestScreen",
                elementsChain: String = "UIButton:attr__class=\"UIButton\""
            ) {
                captureRageClickIfNeeded(
                    touchCoordinates: CGPoint(x: touchX, y: touchY),
                    screenName: screenName,
                    elementsChain: elementsChain,
                    eventData: nil
                )
            }
        }
    #endif
#endif
