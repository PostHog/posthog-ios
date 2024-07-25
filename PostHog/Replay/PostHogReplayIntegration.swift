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
        private let urlInterceptor: URLSessionInterceptor
        private var sessionSwizzler: URLSessionSwizzler?

        // SwiftUI image types
        // https://stackoverflow.com/questions/57554590/how-to-get-all-the-subviews-of-a-window-or-view-in-latest-swiftui-app
        // https://stackoverflow.com/questions/58336045/how-to-detect-swiftui-usage-programmatically-in-an-ios-application
        private let swiftUIImageTypes = ["_TtCOCV7SwiftUI11DisplayList11ViewUpdater8Platform13CGDrawingView",
                                         "_TtC7SwiftUIP33_A34643117F00277B93DEBAB70EC0697122_UIShapeHitTestingView",
                                         "SwiftUI._UIGraphicsView",
                                         "SwiftUI.ImageLayer"].compactMap { NSClassFromString($0) }

        init(_ config: PostHogConfig) {
            self.config = config
            urlInterceptor = URLSessionInterceptor(self.config)
            do {
                try sessionSwizzler = URLSessionSwizzler(interceptor: urlInterceptor)
            } catch {
                hedgeLog("Error trying to Swizzle URLSession: \(error)")
            }
        }

        func start() {
            stopTimer()
            timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                         target: self,
                                         selector: #selector(snapshot),
                                         userInfo: nil,
                                         repeats: true)
            ViewLayoutTracker.swizzleLayoutSubviews()

            UIApplicationTracker.swizzleSendEvent()

            if config.sessionReplayConfig.captureNetworkTelemetry {
                sessionSwizzler?.swizzle()
            }
        }

        func stop() {
            stopTimer()
            ViewLayoutTracker.unSwizzleLayoutSubviews()
            windowViews.removeAllObjects()
            UIApplicationTracker.unswizzleSendEvent()

            sessionSwizzler?.unswizzle()
            urlInterceptor.stop()
        }

        private func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        private func generateSnapshot(_ view: UIView, _ screenName: String? = nil) {
            var hasChanges = false

            let timestamp = Date().toMillis()
            let snapshotStatus = windowViews.object(forKey: view) ?? ViewTreeSnapshotStatus()

            guard let wireframe = config.sessionReplayConfig.screenshotMode ? toScreenshotWireframe(view) : toWireframe(view) else {
                return
            }

            var snapshotsData: [Any] = []

            if !snapshotStatus.sentMetaEvent {
                let size = view.bounds.size
                let width = Int(size.width)
                let height = Int(size.height)

                var data: [String: Any] = ["width": width, "height": height]

                if let screenName = screenName {
                    data["href"] = screenName
                }

                let snapshotData: [String: Any] = ["type": 4, "data": data, "timestamp": timestamp]
                snapshotsData.append(snapshotData)
                snapshotStatus.sentMetaEvent = true
                hasChanges = true
            }

            if hasChanges {
                windowViews.setObject(snapshotStatus, forKey: view)
            }

            // TODO: IncrementalSnapshot, type=2

            var wireframes: [Any] = []
            wireframes.append(wireframe.toDict())
            let initialOffset = ["top": 0, "left": 0]
            let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
            let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
            snapshotsData.append(snapshotData)

            // off the main thread at least the event capture
            DispatchQueue.global().async {
                PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData])
            }
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

        private func createBasicWireframe(_ view: UIView) -> RRWireframe {
            let wireframe = RRWireframe()

            wireframe.id = view.hash
            wireframe.posX = Int(view.frame.origin.x)
            wireframe.posY = Int(view.frame.origin.y)
            wireframe.width = Int(view.frame.size.width)
            wireframe.height = Int(view.frame.size.height)

            return wireframe
        }

        private func findMaskableWidgets(_ view: UIView, _ parent: UIView, _ maskableWidgets: inout [CGRect]) {
            if let textView = view as? UITextView {
                if isTextViewSensitive(textView) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let textField = view as? UITextField {
                if isTextFieldSensitive(textField) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let image = view as? UIImageView {
                if isImageViewSensitive(image) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let label = view as? UILabel {
                if isLabelSensitive(label) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let webView = view as? WKWebView {
                // since we cannot mask the webview content, if masking texts or images are enabled
                // we mask the whole webview as well
                if isAnyInputSensitive(webView) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let button = view as? UIButton {
                if isButtonSensitive(button) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let theSwitch = view as? UISwitch {
                if isSwitchSensitive(theSwitch) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if let picker = view as? UIPickerView {
                if isPickerSensitive(picker) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if swiftUIImageTypes.contains(where: { view.isKind(of: $0) }) {
                if isAnyInputSensitive(view) {
                    maskableWidgets.append(view.toAbsoluteRect(parent))
                    return
                }
            }

            if !view.subviews.isEmpty {
                for child in view.subviews {
                    if !child.isVisible() {
                        continue
                    }

                    findMaskableWidgets(child, parent, &maskableWidgets)
                }
            }
        }

        private func toScreenshotWireframe(_ view: UIView) -> RRWireframe? {
            if !view.isVisible() {
                return nil
            }

            var maskableWidgets: [CGRect] = []
            findMaskableWidgets(view, view, &maskableWidgets)

            let wireframe = createBasicWireframe(view)

            if let image = view.toImage() {
                if !image.size.hasSize() {
                    return nil
                }

                let redactedImage = UIGraphicsImageRenderer(size: image.size, format: .init(for: .init(displayScale: 1))).image { context in
                    context.cgContext.interpolationQuality = .none
                    image.draw(at: .zero)

                    for rect in maskableWidgets {
                        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                        UIColor.black.setFill()
                        path.fill()
                    }
                }
                wireframe.base64 = imageToBase64(redactedImage)
            }
            wireframe.type = "screenshot"
            return wireframe
        }

        private func isAssetsImage(_ image: UIImage) -> Bool {
            // https://github.com/daydreamboy/lldb_scripts#9-pimage
            // do not mask if its an asset image, likely not PII anyway
            image.imageAsset?.value(forKey: "_containingBundle") != nil
        }

        private func isAnyInputSensitive(_ view: UIView) -> Bool {
            isTextInputSensitive(view) || config.sessionReplayConfig.maskAllImages
        }

        private func isTextInputSensitive(_ view: UIView) -> Bool {
            config.sessionReplayConfig.maskAllTextInputs || view.isNoCapture()
        }

        private func isLabelSensitive(_ view: UILabel) -> Bool {
            isTextInputSensitive(view) && hasText(view.text)
        }

        private func isButtonSensitive(_ view: UIButton) -> Bool {
            isTextInputSensitive(view) && hasText(view.titleLabel?.text)
        }

        private func isTextViewSensitive(_ view: UITextView) -> Bool {
            (isTextInputSensitive(view) || view.isSensitiveText()) && hasText(view.text)
        }

        private func isPickerSensitive(_ view: UIPickerView) -> Bool {
            isTextInputSensitive(view) && view.dataSource != nil
        }

        private func isSwitchSensitive(_ view: UISwitch) -> Bool {
            var containsText = true
            if #available(iOS 14.0, *) {
                containsText = hasText(view.title)
            }

            return isTextInputSensitive(view) && containsText
        }

        private func isTextFieldSensitive(_ view: UITextField) -> Bool {
            (isTextInputSensitive(view) || view.isSensitiveText()) && (hasText(view.text) || hasText(view.placeholder))
        }

        private func hasText(_ text: String?) -> Bool {
            if let text = text, !text.isEmpty {
                return true
            } else {
                // if there's no text, there's nothing to mask
                return false
            }
        }

        private func isImageViewSensitive(_ view: UIImageView) -> Bool {
            var isAsset = false
            if let image = view.image {
                isAsset = isAssetsImage(image)
            } else {
                // if there's no image, there's nothing to mask
                return false
            }
            return (config.sessionReplayConfig.maskAllImages && !isAsset) || view.isNoCapture()
        }

        private func toWireframe(_ view: UIView) -> RRWireframe? {
            if !view.isVisible() {
                return nil
            }

            let wireframe = createBasicWireframe(view)

            let style = RRStyle()

            if let textView = view as? UITextView {
                wireframe.type = "text"
                wireframe.text = isTextViewSensitive(textView) ? textView.text.mask() : textView.text
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
                let isSensitive = isTextFieldSensitive(textField)
                if let text = textField.text {
                    wireframe.value = isSensitive ? text.mask() : text
                } else {
                    if let text = textField.placeholder {
                        wireframe.value = isSensitive ? text.mask() : text
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

            if view is UIPickerView {
                wireframe.type = "input"
                wireframe.inputType = "select"
                // set wireframe.value from selected row
            }

            if let theSwitch = view as? UISwitch {
                wireframe.type = "input"
                wireframe.inputType = "toggle"
                wireframe.checked = theSwitch.isOn
                if #available(iOS 14.0, *) {
                    if let text = theSwitch.title {
                        wireframe.label = isSwitchSensitive(theSwitch) ? text.mask() : text
                    }
                }
            }

            if let imageView = view as? UIImageView {
                wireframe.type = "image"
                if let image = imageView.image {
                    if !isImageViewSensitive(imageView) {
                        wireframe.base64 = imageToBase64(image)
                    }
                }
            }

            if let button = view as? UIButton {
                wireframe.type = "input"
                wireframe.inputType = "button"
                wireframe.disabled = !button.isEnabled

                if let text = button.titleLabel?.text {
                    wireframe.value = isButtonSensitive(button) ? text.mask() : text
                }
            }

            if let label = view as? UILabel {
                wireframe.type = "text"
                if let text = label.text {
                    wireframe.text = isLabelSensitive(label) ? text.mask() : text
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
                    if let child = toWireframe(subview) {
                        childWireframes.append(child)
                    }
                }
                wireframe.childWireframes = childWireframes
            }

            return wireframe
        }

        static func getCurrentWindow() -> UIWindow? {
            guard let activeScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) else {
                return nil
            }

            guard let window = (activeScene as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) else {
                return nil
            }
            return window
        }

        @objc private func snapshot() {
            // TODO: add debouncer with debouncerDelayMs to take into account how long it takes to execute the
            // snapshot method

            if !PostHogSDK.shared.isSessionReplayActive() {
                return
            }

            if !ViewLayoutTracker.hasChanges {
                return
            }
            ViewLayoutTracker.clear()

            guard let window = PostHogReplayIntegration.getCurrentWindow() else {
                return
            }

            var screenName: String?
            if let controller = window.rootViewController {
                // SwiftUI only supported with screenshotMode
                if controller is AnyObjectUIHostingViewController, !config.sessionReplayConfig.screenshotMode {
                    hedgeLog("SwiftUI snapshot not supported, enable screenshotMode.")
                    return
                        // screen name only makes sense if we are not using SwiftUI
                } else if !config.sessionReplayConfig.screenshotMode {
                    screenName = UIViewController.getViewControllerName(controller)
                }
            }

            // this cannot run off of the main thread because most properties require to be called within the main thread
            // this method has to be fast and do as little as possible
            generateSnapshot(window, screenName)
        }

        private func imageToBase64(_ image: UIImage) -> String? {
            let jpegData = image.jpegData(compressionQuality: 0.3)
            let base64 = jpegData?.base64EncodedString()

            if let base64 = base64 {
                return "data:image/jpeg;base64,\(base64)"
            }

            return nil
        }
    }

    private protocol AnyObjectUIHostingViewController: AnyObject {}

    extension UIHostingController: AnyObjectUIHostingViewController {}

#endif

// swiftlint:enable cyclomatic_complexity
