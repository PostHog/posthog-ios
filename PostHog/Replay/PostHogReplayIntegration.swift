// swiftlint:disable cyclomatic_complexity

//
//  PostHogReplayIntegration.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS)
    import Foundation
    import PhotosUI
    import SwiftUI
    import UIKit
    import WebKit

    class PostHogReplayIntegration {
        private let config: PostHogConfig

        private var timer: Timer?

        private let windowViews = NSMapTable<UIWindow, ViewTreeSnapshotStatus>.weakToStrongObjects()
        private let urlInterceptor: URLSessionInterceptor
        private var sessionSwizzler: URLSessionSwizzler?

        /**
         ### Mapping of SwiftUI Views to UIKit

         This section summarizes findings on how SwiftUI views map to UIKit components

         #### Image-Based Views
         - **`AsyncImage` and `Image`**
           - Both views have a `CALayer` of type `SwiftUI.ImageLayer`.
           - The associated `UIView` is of type `SwiftUI._UIGraphicsView`.

         #### Graphic-based Views
         - **`Color`, `Divider`, `Gradient` etc
         - These are backed by `SwiftUI._UIGraphicsView` but have a different layer type than images

         #### Text-Based Views
         - **`Text`, `Button`, and `TextEditor`**
           - These views are backed by a `UIView` of type `SwiftUI.CGDrawingView`, which is a subclass of `SwiftUI._UIGraphicsView`.
           - CoreGraphics (`CG`) is used for rendering text content directly, making it challenging to access the value programmatically.

         #### UIKit-Mapped Views
         - **Views Hosted by `UIViewRepresentable`**
           - Some SwiftUI views map directly to UIKit classes or to a subclass:
             - **Control Images** (e.g., in `Picker` drop-downs) may map to `UIImageView`.
             - **Buttons** map to `SwiftUI.UIKitIconPreferringButton` (a subclass of `UIButton`).
             - **Toggle** maps to `UISwitch` (the toggle itself, excluding its label).
             - **Picker** with wheel style maps to `UIPickerView`. Other styles use combinations of image-based and text-based views.

         #### Layout and Structure Views
         - **`Spacer`, `VStack`, `HStack`, `ZStack`, and Lazy Stacks**
           - These views do not correspond to specific a `UIView`. Instead, they translate directly into layout constraints.

         #### List-Based Views
         - **`List` and Scrollable Container Views**
           - Backed by a subclass of `UICollectionView`

         #### Other SwiftUI Views
           - Most other SwiftUI views are *compositions* of the views described above

         SwiftUI Image Types:
           - [StackOverflow: Subviews of a Window or View in SwiftUI](https://stackoverflow.com/questions/57554590/how-to-get-all-the-subviews-of-a-window-or-view-in-latest-swiftui-app)
           - [StackOverflow: Detect SwiftUI Usage Programmatically](https://stackoverflow.com/questions/58336045/how-to-detect-swiftui-usage-programmatically-in-an-ios-application)
         */

        /// `AsyncImage` and `Image`
        private let swiftUIImageLayerTypes = [
            "SwiftUI.ImageLayer",
        ].compactMap(NSClassFromString)

        /// `Text`, `Button`, `TextEditor` views
        private let swiftUITextBasedViewTypes = [
            "SwiftUI.CGDrawingView", // Text, Button
            "SwiftUI.TextEditorTextView", // TextEditor
            "SwiftUI.VerticalTextView", // TextField, vertical axis
        ].compactMap(NSClassFromString)

        private let swiftUIGenericTypes = [
            "_TtC7SwiftUIP33_A34643117F00277B93DEBAB70EC0697122_UIShapeHitTestingView",
        ].compactMap(NSClassFromString)

        private let reactNativeTextView: AnyClass? = NSClassFromString("RCTTextView")
        private let reactNativeImageView: AnyClass? = NSClassFromString("RCTImageView")
        // These are usually views that don't belong to the current process and are most likely sensitive
        private let systemSandboxedView: AnyClass? = NSClassFromString("_UIRemoteView")

        // These layer types should be safe to ignore while masking
        private let swiftUISafeLayerTypes: [AnyClass] = [
            "SwiftUI.GradientLayer", // Views like LinearGradient, RadialGradient, or AngularGradient
        ].compactMap(NSClassFromString)

        static let dispatchQueue = DispatchQueue(label: "com.posthog.PostHogReplayIntegration",
                                                 target: .global(qos: .utility))

        init(_ config: PostHogConfig) {
            self.config = config
            urlInterceptor = URLSessionInterceptor(self.config)
            do {
                try sessionSwizzler = URLSessionSwizzler(interceptor: urlInterceptor)
            } catch {
                hedgeLog("Error trying to Swizzle URLSession: \(error)")
            }
        }

        private func isNotFlutter() -> Bool {
            postHogSdkName != "posthog-flutter"
        }

        func start() {
            stopTimer()
            // reset views when session id changes (or is cleared) so we can re-send new metadata (or full snapshot in the future)
            PostHogSessionManager.shared.onSessionIdChanged = resetViews

            // flutter captures snapshots, so we don't need to capture them here
            if isNotFlutter() {
                DispatchQueue.main.async {
                    self.timer = Timer.scheduledTimer(withTimeInterval: self.config.sessionReplayConfig.debouncerDelay, repeats: true, block: { _ in
                        self.snapshot()
                    })
                }
                ViewLayoutTracker.swizzleLayoutSubviews()
            }

            UIApplicationTracker.swizzleSendEvent()

            if config.sessionReplayConfig.captureNetworkTelemetry {
                sessionSwizzler?.swizzle()
            }
        }

        func stop() {
            stopTimer()
            resetViews()
            PostHogSessionManager.shared.onSessionIdChanged = {}

            ViewLayoutTracker.unSwizzleLayoutSubviews()
            UIApplicationTracker.unswizzleSendEvent()
            sessionSwizzler?.unswizzle()
            urlInterceptor.stop()
        }

        func isActive() -> Bool {
            timer != nil
        }

        private func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        private func resetViews() {
            windowViews.removeAllObjects()
        }

        private func generateSnapshot(_ window: UIWindow, _ screenName: String? = nil) {
            var hasChanges = false

            guard let wireframe = config.sessionReplayConfig.screenshotMode ? toScreenshotWireframe(window) : toWireframe(window) else {
                return
            }

            // capture timestamp after snapshot was taken
            let timestampDate = Date()
            let timestamp = timestampDate.toMillis()

            let snapshotStatus = windowViews.object(forKey: window) ?? ViewTreeSnapshotStatus()

            // always make sure we have a fresh session id at correct timestamp
            guard let sessionId = PostHogSessionManager.shared.getSessionId(at: timestampDate) else {
                return
            }

            var snapshotsData: [Any] = []

            if !snapshotStatus.sentMetaEvent {
                let size = window.bounds.size
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
                windowViews.setObject(snapshotStatus, forKey: window)
            }

            // TODO: IncrementalSnapshot, type=2

            PostHogReplayIntegration.dispatchQueue.async {
                var wireframes: [Any] = []
                wireframes.append(wireframe.toDict())
                let initialOffset = ["top": 0, "left": 0]
                let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
                let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
                snapshotsData.append(snapshotData)

                PostHogSDK.shared.capture(
                    "$snapshot",
                    properties: [
                        "$snapshot_source": "mobile",
                        "$snapshot_data": snapshotsData,
                        "$session_id": sessionId,
                    ],
                    timestamp: timestampDate
                )
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

            // since FE will render each node of the wireframe with position: fixed
            // we need to convert bounds to global screen coordinates
            // otherwise each view of depth > 1 will likely have an origin of 0,0 (which is the local origin)
            let frame = view.toAbsoluteRect(view.window)

            wireframe.id = view.hash
            wireframe.posX = Int(frame.origin.x)
            wireframe.posY = Int(frame.origin.y)
            wireframe.width = Int(frame.size.width)
            wireframe.height = Int(frame.size.height)

            return wireframe
        }

        private func findMaskableWidgets(_ view: UIView, _ window: UIWindow, _ maskableWidgets: inout [CGRect], _ maskChildren: inout Bool) {
            // User explicitly marked this view (and its subviews) as non-maskable through `.postHogNoMask()` view modifier
            if view.postHogNoMask {
                return
            }

            if let textView = view as? UITextView { // TextEditor, SwiftUI.TextEditorTextView, SwiftUI.UIKitTextView
                if isTextViewSensitive(textView) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            /// SwiftUI: `TextField`, `SecureField` will land here
            if let textField = view as? UITextField {
                if isTextFieldSensitive(textField) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            if let reactNativeTextView = reactNativeTextView {
                if view.isKind(of: reactNativeTextView), config.sessionReplayConfig.maskAllTextInputs {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            /// SwiftUI: Some control images like the ones in `Picker` view may land here
            if let image = view as? UIImageView {
                if isImageViewSensitive(image) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            if let reactNativeImageView = reactNativeImageView {
                if view.isKind(of: reactNativeImageView), config.sessionReplayConfig.maskAllImages {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            if let label = view as? UILabel { // Text, this code might never be reachable in SwiftUI, see swiftUIImageTypes instead
                if isLabelSensitive(label) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            if let webView = view as? WKWebView { // Link, this code might never be reachable in SwiftUI, see swiftUIImageTypes instead
                // since we cannot mask the webview content, if masking texts or images are enabled
                // we mask the whole webview as well
                if isAnyInputSensitive(webView) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            /// SwiftUI: `SwiftUI.UIKitIconPreferringButton` and other subclasses will land here
            if let button = view as? UIButton {
                if isButtonSensitive(button) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            /// SwiftUI: `Toggle` (no text, labels are just rendered to Text (swiftUIImageTypes))
            if let theSwitch = view as? UISwitch {
                if isSwitchSensitive(theSwitch) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            // detect any views that don't belong to the current process (likely system views)
            if config.sessionReplayConfig.maskAllSandboxedViews,
               let systemSandboxedView,
               view.isKind(of: systemSandboxedView)
            {
                maskableWidgets.append(view.toAbsoluteRect(window))
                return
            }

            // if its a generic type and has subviews, subviews have to be checked first
            let hasSubViews = !view.subviews.isEmpty

            /// SwiftUI: `Picker` with .pickerStyle(.wheel) will land here
            if let picker = view as? UIPickerView {
                if isTextInputSensitive(picker), !hasSubViews {
                    maskableWidgets.append(picker.toAbsoluteRect(window))
                    return
                }
            }

            /// SwiftUI: Text based views like `Text`, `Button`, `TextEditor`
            if swiftUITextBasedViewTypes.contains(where: view.isKind(of:)) {
                if isTextInputSensitive(view), !hasSubViews {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            /// SwiftUI: Image based views like `Image`, `AsyncImage`. (Note: We check the layer type here)
            if swiftUIImageLayerTypes.contains(where: view.layer.isKind(of:)) {
                if isSwiftUIImageSensitive(view), !hasSubViews {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            // this can be anything, so better to be conservative
            if swiftUIGenericTypes.contains(where: { view.isKind(of: $0) }), !isSwiftUILayerSafe(view.layer) {
                if isTextInputSensitive(view), !hasSubViews {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            }

            // manually masked views through `.postHogMask()` view modifier
            if view.postHogNoCapture {
                maskableWidgets.append(view.toAbsoluteRect(window))
                return
            }

            // on RN, lots get converted to RCTRootContentView, RCTRootView, RCTView and sometimes its just the whole screen, we dont want to mask
            // in such cases
            if view.isNoCapture() || maskChildren {
                let viewRect = view.toAbsoluteRect(window)
                let windowRect = window.frame

                // Check if the rectangles do not match
                if !viewRect.equalTo(windowRect) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                } else {
                    maskChildren = true
                }
            }

            if !view.subviews.isEmpty {
                for child in view.subviews {
                    if !child.isVisible() {
                        continue
                    }

                    findMaskableWidgets(child, window, &maskableWidgets, &maskChildren)
                }
            }
            maskChildren = false
        }

        private func toScreenshotWireframe(_ window: UIWindow) -> RRWireframe? {
            // this will bail on interactive animations (e.g edge slide)
            if !window.isVisible() || isAnimatingTransition(window) {
                return nil
            }

            var maskableWidgets: [CGRect] = []
            var maskChildren = false
            findMaskableWidgets(window, window, &maskableWidgets, &maskChildren)

            let wireframe = createBasicWireframe(window)

            if let image = window.toImage() {
                if !image.size.hasSize() {
                    return nil
                }

                wireframe.maskableWidgets = maskableWidgets

                wireframe.image = image
            }
            wireframe.type = "screenshot"
            return wireframe
        }

        /// Check if window's root view controller is animating a transition
        private func isAnimatingTransition(_ window: UIWindow) -> Bool {
            window.rootViewController?.transitionCoordinator?.isAnimated ?? false
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

        private func isSwiftUILayerSafe(_ layer: CALayer) -> Bool {
            swiftUISafeLayerTypes.contains(where: { layer.isKind(of: $0) })
        }

        private func hasText(_ text: String?) -> Bool {
            if let text = text, !text.isEmpty {
                return true
            } else {
                // if there's no text, there's nothing to mask
                return false
            }
        }

        private func isSwiftUIImageSensitive(_ view: UIView) -> Bool {
            // No way of checking if this is an asset image or not
            // No way of checking if there's actual content in the image or not
            config.sessionReplayConfig.maskAllImages || view.isNoCapture()
        }

        private func isImageViewSensitive(_ view: UIImageView) -> Bool {
            // if there's no image, there's nothing to mask
            guard let image = view.image else { return false }

            // sensitive, regardless
            if view.isNoCapture() {
                return true
            }

            // asset images are probably not sensitive
            if isAssetsImage(image) {
                return false
            }

            // symbols are probably not sensitive
            if image.isSymbolImage {
                return false
            }

            return config.sessionReplayConfig.maskAllImages
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
                        wireframe.image = image
                    }
                }
            }

            if let button = view as? UIButton {
                wireframe.type = "input"
                wireframe.inputType = "button"
                wireframe.disabled = !button.isEnabled

                if let text = button.titleLabel?.text {
                    // NOTE: this will create a ghosting effect since text will also be captured in child UILabel
                    //       We also may be masking this UIButton but child UILabel may remain unmasked
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

        @objc private func snapshot() {
            if !PostHogSDK.shared.isSessionReplayActive() {
                return
            }

            if !ViewLayoutTracker.hasChanges {
                return
            }
            ViewLayoutTracker.clear()

            guard let window = UIApplication.getCurrentWindow() else {
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
    }

    private protocol AnyObjectUIHostingViewController: AnyObject {}

    extension UIHostingController: AnyObjectUIHostingViewController {}

#endif

// swiftlint:enable cyclomatic_complexity
