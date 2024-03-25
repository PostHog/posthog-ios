// swiftlint:disable cyclomatic_complexity

//
//  PostHogReplayIntegration.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS)
    import Foundation
    import SwiftUI
    import UIKit
    import WebKit

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

        private func generateSnapshot(_ view: UIView, _ screenName: String? = nil) {
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

                var data: [String: Any] = ["width": width, "height": height]

                if screenName != nil {
                    data["href"] = screenName
                }

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

        private func setAlignment(_ alignment: NSTextAlignment, _ style: RRStyle) {
            if alignment == .center {
                style.verticalAlign = "center"
                style.horizontalAlign = "center"
            } else if alignment == .right {
                style.horizontalAlign = "right"
            } else if alignment == .left {
                style.horizontalAlign = "left"
            }
        }

        private func setPadding(_ insets: UIEdgeInsets, _ style: RRStyle) {
            style.paddingTop = Int(insets.top)
            style.paddingRight = Int(insets.right)
            style.paddingBottom = Int(insets.bottom)
            style.paddingLeft = Int(insets.left)
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
                setAlignment(textView.textAlignment, style)
                setPadding(textView.textContainerInset, style)
            }

            if let textField = view as? UITextField {
                wireframe.type = "input"
                wireframe.inputType = "text_area"
                if let text = textField.text {
                    wireframe.value = (textField.isNoCapture() || textField.isSensitiveText()) ? text.mask() : text
                } else {
                    if let text = textField.placeholder {
                        wireframe.value = (textField.isNoCapture() || textField.isSensitiveText()) ? text.mask() : text
                    }
                }
                wireframe.disabled = !textField.isEnabled
                style.color = textField.textColor?.toRGBString()
                style.fontFamily = textField.font?.familyName
                if let fontSize = textField.font?.pointSize {
                    style.fontSize = Int(fontSize)
                }
                setAlignment(textField.textAlignment, style)
            }

            if let picker = view as? UIPickerView {
                wireframe.type = "input"
                wireframe.inputType = "select"
            }

            if let theSwitch = view as? UISwitch {
                wireframe.type = "input"
                wireframe.inputType = "toggle"
                wireframe.checked = theSwitch.isOn
            }

            if let image = view as? UIImageView {
                wireframe.type = "image"
                if !image.isNoCapture() {
                    // TODO: check png quality
                    wireframe.base64 = image.image?.pngData()?.base64EncodedString()
                }
            }

            if let button = view as? UIButton {
                wireframe.type = "input"
                wireframe.inputType = "button"
                wireframe.disabled = !button.isEnabled

                if let text = button.titleLabel?.text {
                    wireframe.value = button.isNoCapture() ? text.mask() : text
                }
            }

            if let label = view as? UILabel {
                wireframe.type = "text"
                if let text = label.text {
                    wireframe.text = label.isNoCapture() ? text.mask() : text
                }
                wireframe.disabled = !label.isEnabled
                style.color = label.textColor?.toRGBString()
                style.fontFamily = label.font?.familyName
                if let fontSize = label.font?.pointSize {
                    style.fontSize = Int(fontSize)
                }
                setAlignment(label.textAlignment, style)
            }

            if view is WKWebView {
                wireframe.type = "web_view"
            }

            if let progressView = view as? UIProgressView {
                wireframe.type = "input"
                wireframe.inputType = "progress"
                wireframe.value = progressView.progress
                wireframe.max = 1
                // UIProgressView theres not circular format, only custom view or swiftui
                style.bar = "horizontal"
            }

            if view is UIActivityIndicatorView {
                wireframe.type = "input"
                wireframe.inputType = "progress"
                style.bar = "circular"
            }

            // TODO: props: backgroundImage (probably not needed)
            // TODO: componenets: UITabBar, UINavigationBar, UISlider, UIStepper, UIDatePicker

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

            var screenName: String?
            if let controller = window.rootViewController {
                if controller is AnyObjectUIHostingViewController {
                    hedgeLog("SwiftUI snapshot not supported.")
                    return
                }
                screenName = UIViewController.getViewControllerName(controller)
            }

            // this cannot run off of the main thread because most properties require to be called within the main thread
            // this method has to be fast and do as little as possible
            generateSnapshot(window, screenName)
        }
    }

    private protocol AnyObjectUIHostingViewController: AnyObject {}

    extension UIHostingController: AnyObjectUIHostingViewController {}

#endif

// swiftlint:enable cyclomatic_complexity
