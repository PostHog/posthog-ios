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

            swizzle(forClass: UIApplication.self,
                    original: #selector(UIApplication.sendEventOverride),
                    new: #selector(UIApplication.sendEvent(_:)))
            hasSwizzled = false
        }
    }

    extension UIApplication {
        @objc func sendEventOverride(_ event: UIEvent) {
            // touch.timestamp is since boot time so we need to get the current time, best effort
            let timestamp = Date().toMillis()
            sendEventOverride(event)

            if !PostHogSDK.shared.isSessionReplayActive() {
                return
            }

            guard event.type == .touches else {
                return
            }
            guard let window = PostHogReplayIntegration.getCurrentWindow() else {
                return
            }

            guard let touches = event.touches(for: window) else {
                return
            }

            var snapshotsData: [Any] = []
            for touch in touches {
                let phase = touch.phase

                let type: Int
                if phase == .began {
                    type = 7
                } else if phase == .ended {
                    type = 9
                } else {
                    continue
                }

                let posX = Int(touch.location(in: window).x)
                let posY = Int(touch.location(in: window).y)

                // if the id is 0, BE transformer will set it to the virtual bodyId
                let touchData: [String: Any] = ["id": 0, "pointerType": 2, "source": 2, "type": type, "x": posX, "y": posY]

                let data: [String: Any] = ["type": 3, "data": touchData, "timestamp": timestamp]
                snapshotsData.append(data)
            }
            if !snapshotsData.isEmpty {
                DispatchQueue.global().async {
                    PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData])
                }
            }
        }
    }
#endif
