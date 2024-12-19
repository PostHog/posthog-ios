//
//  UIApplicationTracker.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 26.03.24.
//

#if os(iOS)
    import Foundation
    import UIKit

    enum UIApplicationTracker {
        private static var hasSwizzled = false

        static func swizzleSendEvent() {
            if hasSwizzled {
                return
            }

            swizzle(forClass: UIApplication.self,
                    original: #selector(UIApplication.sendEvent(_:)),
                    new: #selector(UIApplication.sendEventOverride))
            hasSwizzled = true
        }

        static func unswizzleSendEvent() {
            if !hasSwizzled {
                return
            }

            // swizzling twice will exchange implementations back to original
            swizzle(forClass: UIApplication.self,
                    original: #selector(UIApplication.sendEvent(_:)),
                    new: #selector(UIApplication.sendEventOverride))
            hasSwizzled = false
        }
    }

    extension UIApplication {
        private func captureEvent(_ event: UIEvent, date: Date) {
            if !PostHogSDK.shared.isSessionReplayActive() {
                return
            }

            guard event.type == .touches else {
                return
            }
            guard let window = UIApplication.getCurrentWindow() else {
                return
            }
            guard let touches = event.touches(for: window) else {
                return
            }

            // always make sure we have a fresh session id as early as possible
            guard let sessionId: String = PostHogSessionManager.shared.getSessionId(at: date) else {
                return
            }

            // capture necessary touch information on the main thread before performing any asynchronous operations
            // - this ensures that UITouch associated objects like UIView, UIWindow, or [UIGestureRecognizer] are still valid.
            // - these objects may be released or erased by the system if accessed asynchronously, resulting in invalid/zeroed-out touch coordinates
            let touchInfo = touches.map {
                (phase: $0.phase, location: $0.location(in: window))
            }

            PostHogReplayIntegration.dispatchQueue.async { [touchInfo] in
                var snapshotsData: [Any] = []
                for touch in touchInfo {
                    let phase = touch.phase

                    let type: Int
                    if phase == .began {
                        type = 7
                    } else if phase == .ended {
                        type = 9
                    } else {
                        continue
                    }

                    // we keep a failsafe here just in case, but this will likely never be triggered
                    guard touch.location != .zero else {
                        continue
                    }

                    let posX = Int(touch.location.x)
                    let posY = Int(touch.location.y)

                    // if the id is 0, BE transformer will set it to the virtual bodyId
                    let touchData: [String: Any] = ["id": 0, "pointerType": 2, "source": 2, "type": type, "x": posX, "y": posY]

                    let data: [String: Any] = ["type": 3, "data": touchData, "timestamp": date.toMillis()]
                    snapshotsData.append(data)
                }
                if !snapshotsData.isEmpty {
                    PostHogSDK.shared.capture(
                        "$snapshot",
                        properties: [
                            "$snapshot_source": "mobile",
                            "$snapshot_data": snapshotsData,
                            "$session_id": sessionId,
                        ],
                        timestamp: date
                    )
                }
            }
        }

        @objc func sendEventOverride(_ event: UIEvent) {
            // touch.timestamp is since boot time so we need to get the current time, best effort
            let date = Date()
            captureEvent(event, date: date)
            sendEventOverride(event)
            // update "last active" session
            // we want to keep track of the idle time, so we need to maintain a timestamp on the last interactions of the user with the app. UIEvents are a good place to do so since it means that the user is actively interacting with the app (e.g not just noise background activity)
            PostHogSessionManager.shared.touchSession()
        }
    }
#endif
