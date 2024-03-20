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
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            let snapshotStatus = windowViews.object(forKey: view) ?? ViewTreeSnapshotStatus()

            var hasChanges = false

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
            // TODO: thread safe
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
