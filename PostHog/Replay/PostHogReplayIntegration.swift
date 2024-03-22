//
//  PostHogReplayIntegration.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS) || os(tvOS)
    import Foundation
    import UIKit

    class PostHogReplayIntegration {
        private let config: PostHogConfig

        private let timeInterval = 1.0 / 2.0
        private var timer: Timer?

        private let windowViews = NSMapTable<UIView, ViewTreeSnapshotStatus>.weakToStrongObjects()

        init(_ config: PostHogConfig) {
            self.config = config
        }

        func start() {
            stopTimer()
            timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                         target: self,
                                         selector: #selector(snapshot),
                                         userInfo: nil,
                                         repeats: true)
            ViewLayoutTracker.swizzleLayoutSubviews()
        }

        func stop() {
            stopTimer()
            ViewLayoutTracker.unSwizzleLayoutSubviews()
            windowViews.removeAllObjects()
        }

        private func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        private func generateSnapshot(_ view: UIView) {
            var hasChanges = false

            let timestamp = Date().toMillis()
            let snapshotStatus = windowViews.object(forKey: view) ?? ViewTreeSnapshotStatus()

            guard let wireframe = toWireframe(view) else {
                return
            }

            if !snapshotStatus.sentMetaEvent {
                let size = view.bounds.size
                let width = Int(size.width)
                let height = Int(size.height)

                // TODO: set href
                let data: [String: Any] = ["width": width, "height": height]
                let snapshotData: [String: Any] = ["type": 4, "data": data, "timestamp": timestamp]
                PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotData])
                snapshotStatus.sentMetaEvent = true
                hasChanges = true
            }

            if hasChanges {
                windowViews.setObject(snapshotStatus, forKey: view)
            }

            var wireframes: [Any] = []
            wireframes.append(wireframe.toDict())
            let initialOffset = ["top": 0, "left": 0]
            let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
            let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
            PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotData])
        }

        private func toWireframe(_ view: UIView, parentId: Int? = nil) -> RRWireframe? {
            if !view.isVisible() {
                return nil
            }

            let wireframe = RRWireframe()

            wireframe.id = view.hash
            wireframe.posX = Int(view.frame.origin.x)
            wireframe.posY = Int(view.frame.origin.y)
            wireframe.width = Int(view.frame.size.width)
            wireframe.height = Int(view.frame.size.height)
            let style = RRStyle()

            if let textView = view as? UITextView {
                wireframe.type = "text"
                wireframe.text = (textView.isNoCapture() || textView.isSensitiveText()) ? textView.text.mask() : textView.text
                wireframe.disabled = !textView.isEditable
                style.color = textView.textColor?.toRGBString()
                style.fontFamily = textView.font?.familyName
                if let fontSize = textView.font?.pointSize {
                    style.fontSize = Int(fontSize)
                }
            }

            // TODO: missing horizontalAlign, verticalAlign, paddings, backgroundImage

            style.backgroundColor = view.backgroundColor?.toRGBString()
            let layer = view.layer
            style.borderWidth = Int(layer.borderWidth)
            style.borderRadius = Int(layer.cornerRadius)
            style.borderColor = layer.borderColor?.toRGBString()

            wireframe.style = style

            if !view.subviews.isEmpty {
                var childWireframes: [RRWireframe] = []
                for subview in view.subviews {
                    if let child = toWireframe(subview, parentId: view.hash) {
                        childWireframes.append(child)
                    }
                }
                wireframe.childWireframes = childWireframes
            }

            return wireframe
        }

        private func isSessionActive() -> Bool {
            config.sessionReplay && PostHogSDK.shared.isSessionActive()
        }

        @objc private func snapshot() {
            if !isSessionActive() {
                return
            }

            if !ViewLayoutTracker.hasChanges {
                return
            }
            ViewLayoutTracker.clear()

            guard let activeScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) else {
                return
            }

            guard let window = (activeScene as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) else {
                return
            }

            // TODO: offload conversion to off main thread
            generateSnapshot(window)
        }
    }
#endif
