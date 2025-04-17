// swiftlint:disable cyclomatic_complexity

//
//  PostHogReplayIntegration.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS)
    import CoreImage.CIFilterBuiltins
    import Foundation
    import PhotosUI
    import SafariServices
    import SwiftUI
    import UIKit
    import WebKit

    class PostHogReplayIntegration: PostHogIntegration {
        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private var config: PostHogConfig? {
            postHog?.config
        }

        private weak var postHog: PostHogSDK?

        private var isEnabled: Bool = false

        private let windowViewsLock = NSLock()
        private let windowViews = NSMapTable<UIWindow, ViewTreeSnapshotStatus>.weakToStrongObjects()
        private var urlInterceptor: URLSessionInterceptor?
        private var sessionSwizzler: URLSessionSwizzler?
        private var applicationEventToken: RegistrationToken?
        private var viewLayoutToken: RegistrationToken?

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

        private func isNotFlutter() -> Bool {
            // for the Flutter SDK, screen recordings are managed by Flutter SDK itself
            postHogSdkName != "posthog-flutter"
        }

        func install(_ postHog: PostHogSDK) throws {
            try PostHogReplayIntegration.integrationInstalledLock.withLock {
                if PostHogReplayIntegration.integrationInstalled {
                    throw InternalPostHogError(description: "Replay integration already installed to another PostHogSDK instance.")
                }
                PostHogReplayIntegration.integrationInstalled = true
            }

            self.postHog = postHog
            let interceptor = URLSessionInterceptor(postHog)
            urlInterceptor = interceptor
            do {
                try sessionSwizzler = URLSessionSwizzler(interceptor: interceptor)
            } catch {
                hedgeLog("Error trying to Swizzle URLSession: \(error)")
            }

            start()
        }

        func uninstall(_ postHog: PostHogSDK) {
            if self.postHog === postHog || self.postHog == nil {
                stop()
                urlInterceptor = nil
                sessionSwizzler = nil
                self.postHog = nil
                PostHogReplayIntegration.integrationInstalledLock.withLock {
                    PostHogReplayIntegration.integrationInstalled = false
                }
            }
        }

        func start() {
            guard let postHog else {
                return
            }

            isEnabled = true
            // reset views when session id changes (or is cleared) so we can re-send new metadata (or full snapshot in the future)
            PostHogSessionManager.shared.onSessionIdChanged = { [weak self] in
                self?.resetViews()
            }

            // flutter captures snapshots, so we don't need to capture them here
            if isNotFlutter() {
                let interval = postHog.config.sessionReplayConfig.throttleDelay
                viewLayoutToken = DI.main.viewLayoutPublisher.onViewLayout(throttle: interval) { [weak self] in
                    // called on main thread
                    self?.snapshot()
                }
            }

            // start listening to `UIApplication.sendEvent`
            let applicationEventPublisher = DI.main.applicationEventPublisher
            applicationEventToken = applicationEventPublisher.onApplicationEvent { [weak self] event, date in
                self?.handleApplicationEvent(event: event, date: date)
            }

            if postHog.config.sessionReplayConfig.captureNetworkTelemetry {
                sessionSwizzler?.swizzle()
            }
        }

        func stop() {
            isEnabled = false
            resetViews()
            PostHogSessionManager.shared.onSessionIdChanged = {}

            // stop listening to `UIApplication.sendEvent`
            applicationEventToken = nil
            // stop listening to `UIView.layoutSubviews` events
            viewLayoutToken = nil

            sessionSwizzler?.unswizzle()
            urlInterceptor?.stop()
        }

        func isActive() -> Bool {
            isEnabled
        }

        private func resetViews() {
            // Ensure thread-safe access to windowViews
            windowViewsLock.withLock {
                windowViews.removeAllObjects()
            }
        }

        private func handleApplicationEvent(event: UIEvent, date: Date) {
            guard let postHog, postHog.isSessionReplayActive() else {
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
            guard let sessionId = PostHogSessionManager.shared.getSessionId(at: date) else {
                return
            }

            // capture necessary touch information on the main thread before performing any asynchronous operations
            // - this ensures that UITouch associated objects like UIView, UIWindow, or [UIGestureRecognizer] are still valid.
            // - these objects may be released or erased by the system if accessed asynchronously, resulting in invalid/zeroed-out touch coordinates
            let touchInfo = touches.map {
                (phase: $0.phase, location: $0.location(in: window))
            }

            PostHogReplayIntegration.dispatchQueue.async { [touchInfo, weak postHog = postHog] in
                // captured weakly since integration may have uninstalled by now
                guard let postHog else { return }

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

                    let posX = touch.location.x.toInt()
                    let posY = touch.location.y.toInt()

                    // if the id is 0, BE transformer will set it to the virtual bodyId
                    let touchData: [String: Any] = ["id": 0, "pointerType": 2, "source": 2, "type": type, "x": posX, "y": posY]

                    let data: [String: Any] = ["type": 3, "data": touchData, "timestamp": date.toMillis()]
                    snapshotsData.append(data)
                }
                if !snapshotsData.isEmpty {
                    postHog.capture(
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

        private func generateSnapshot(_ window: UIWindow, _ screenName: String? = nil, postHog: PostHogSDK) {
            var hasChanges = false

            guard let wireframe = postHog.config.sessionReplayConfig.screenshotMode ? toScreenshotWireframe(window) : toWireframe(window) else {
                return
            }

            // capture timestamp after snapshot was taken
            let timestampDate = Date()
            let timestamp = timestampDate.toMillis()

            let snapshotStatus = windowViewsLock.withLock {
                windowViews.object(forKey: window) ?? ViewTreeSnapshotStatus()
            }

            // always make sure we have a fresh session id at correct timestamp
            guard let sessionId = PostHogSessionManager.shared.getSessionId(at: timestampDate) else {
                return
            }

            var snapshotsData: [Any] = []

            if !snapshotStatus.sentMetaEvent {
                let size = window.bounds.size
                let width = size.width.toInt()
                let height = size.height.toInt()

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
                windowViewsLock.withLock {
                    windowViews.setObject(snapshotStatus, forKey: window)
                }
            }

            // TODO: IncrementalSnapshot, type=2

            PostHogReplayIntegration.dispatchQueue.async {
                var wireframes: [Any] = []
                wireframes.append(wireframe.toDict())
                let initialOffset = ["top": 0, "left": 0]
                let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
                let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
                snapshotsData.append(snapshotData)

                postHog.capture(
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
            style.paddingTop = insets.top.toInt()
            style.paddingRight = insets.right.toInt()
            style.paddingBottom = insets.bottom.toInt()
            style.paddingLeft = insets.left.toInt()
        }

        private func createBasicWireframe(_ view: UIView) -> RRWireframe {
            let wireframe = RRWireframe()

            // since FE will render each node of the wireframe with position: fixed
            // we need to convert bounds to global screen coordinates
            // otherwise each view of depth > 1 will likely have an origin of 0,0 (which is the local origin)
            let frame = view.toAbsoluteRect(view.window)

            wireframe.id = view.hash
            wireframe.posX = frame.origin.x.toInt()
            wireframe.posY = frame.origin.y.toInt()
            wireframe.width = frame.size.width.toInt()
            wireframe.height = frame.size.height.toInt()

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
                if view.isKind(of: reactNativeTextView), config?.sessionReplayConfig.maskAllTextInputs == true {
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
                if view.isKind(of: reactNativeImageView), config?.sessionReplayConfig.maskAllImages == true {
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
            if config?.sessionReplayConfig.maskAllSandboxedViews == true,
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
            // this will bail on view controller animations (interactive or not)
            if !window.isVisible() {
                return nil
            }

            guard let snapshotImage = window.renderWithMasking() else {
                return nil
            }

            if !snapshotImage.size.hasSize() {
                return nil
            }

            let wireframe = createBasicWireframe(window)
            wireframe.type = "screenshot"
            wireframe.image = snapshotImage

            return wireframe
        }

        /// Check if any view controller in the hierarchy is animating a transition
        private func isAnimatingTransition(_ window: UIWindow) -> Bool {
            guard let rootViewController = window.rootViewController else { return false }
            return isAnimatingTransition(rootViewController)
        }

        private func isAnimatingTransition(_ viewController: UIViewController) -> Bool {
            // Check if this view controller is animating
            if viewController.transitionCoordinator?.isAnimated ?? false {
                return true
            }

            // Check if presented view controller is animating
            if let presented = viewController.presentedViewController, isAnimatingTransition(presented) {
                return true
            }

            // Check if any of the child view controllers is animating
            if viewController.children.first(where: isAnimatingTransition) != nil {
                return true
            }

            return false
        }

        private func isAssetsImage(_ image: UIImage) -> Bool {
            // https://github.com/daydreamboy/lldb_scripts#9-pimage
            // do not mask if its an asset image, likely not PII anyway
            image.imageAsset?.value(forKey: "_containingBundle") != nil
        }

        private func isAnyInputSensitive(_ view: UIView) -> Bool {
            isTextInputSensitive(view) || config?.sessionReplayConfig.maskAllImages == true
        }

        private func isTextInputSensitive(_ view: UIView) -> Bool {
            config?.sessionReplayConfig.maskAllTextInputs == true || view.isNoCapture()
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
            config?.sessionReplayConfig.maskAllImages == true || view.isNoCapture()
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

            return config?.sessionReplayConfig.maskAllImages == true
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
                if let fontSize = textView.font?.pointSize.toInt() {
                    style.fontSize = fontSize
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
                if let fontSize = textField.font?.pointSize.toInt() {
                    style.fontSize = fontSize
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
                if let fontSize = label.font?.pointSize.toInt() {
                    style.fontSize = fontSize
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
            style.borderWidth = layer.borderWidth.toInt()
            style.borderRadius = layer.cornerRadius.toInt()
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
            guard let postHog, postHog.isSessionReplayActive() else {
                return
            }

            guard let window = UIApplication.getCurrentWindow() else {
                return
            }

            var screenName: String?
            if let controller = window.rootViewController {
                // SwiftUI only supported with screenshotMode
                if controller is AnyObjectUIHostingViewController, !postHog.config.sessionReplayConfig.screenshotMode {
                    hedgeLog("SwiftUI snapshot not supported, enable screenshotMode.")
                    return
                        // screen name only makes sense if we are not using SwiftUI
                } else if !postHog.config.sessionReplayConfig.screenshotMode {
                    screenName = UIViewController.getViewControllerName(controller)
                }
            }

            // this cannot run off of the main thread because most properties require to be called within the main thread
            // this method has to be fast and do as little as possible
            generateSnapshot(window, screenName, postHog: postHog)
        }
    }

    private protocol AnyObjectUIHostingViewController: AnyObject {}

    extension UIHostingController: AnyObjectUIHostingViewController {}

//    func snapshotWithSanitizedText(from view: UIView, callback: ((UIImage) -> Void)?) {
//        // Create a renderer with the bounds of the view
//        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
//        var restorations: [() -> Void] = []
//
//        // Generate the snapshot
//        let snapshot = renderer.image { context in
//            // Recursive function to draw the view hierarchy with sanitized text
//            func drawSanitizedHierarchy(in view: UIView) {
//                // Check for text-containing views and sanitize them
//                if let textField = view as? UITextField {
//                    let originalIsHidden = textField.isHidden
//                    textField.isHidden = true
//                    restorations.append { textField.isHidden = originalIsHidden }
//
//                    // Replace text with sanitized text
//                    let label = UILabel(frame: textField.frame)
//                    label.text = "****"
//                    label.font = textField.font
//                    label.textAlignment = textField.textAlignment
//                    label.drawHierarchy(in: label.bounds, afterScreenUpdates: true)
//                } else if let textView = view as? UITextView {
//                    let originalIsHidden = textView.isHidden
//                    textView.isHidden = true
//                    restorations.append { textView.isHidden = originalIsHidden }
//
//                    let label = UILabel(frame: textView.frame)
//                    label.text = "****"
//                    label.font = textView.font
//                    label.textAlignment = textView.textAlignment
//                    label.drawHierarchy(in: label.bounds, afterScreenUpdates: true)
//                } else {
//                    // If not a text-containing view, draw the view as is
//                    view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
//                }
//
//                // Recursively sanitize and draw subviews
//                for subview in view.subviews {
//                    context.cgContext.saveGState() // Save the current graphics state
//                    context.cgContext.translateBy(x: subview.frame.origin.x, y: subview.frame.origin.y)
//                    drawSanitizedHierarchy(in: subview)
//                    for restoration in restorations {
//                        restoration()
//                    }
//                    context.cgContext.restoreGState() // Restore the previous graphics state
//                }
//            }
//
//            // Start the sanitization and drawing process
//            drawSanitizedHierarchy(in: view)
//        }
//
//        // Call the callback with the snapshot
//        callback?(snapshot)
//    }

    let swiftUIImageLayerTypes = [
        "SwiftUI.ImageLayer",
    ].compactMap(NSClassFromString)

    let swiftUITextBasedViewTypes = [
        "SwiftUI.CGDrawingView", // Text, Button
        "SwiftUI.TextEditorTextView", // TextEditor
        "SwiftUI.VerticalTextView", // TextField, vertical axis
    ].compactMap(NSClassFromString)

    extension UIView {
        func drawHierarchyWithMasking(
            in context: CGContext
        ) {
            context.saveGState()

            let globalFrame = convert(bounds, to: window)
            context.concatenate(transform)
            context.translateBy(x: globalFrame.origin.x, y: globalFrame.origin.y)

            // Draw the current layer
            if swiftUITextBasedViewTypes.contains(where: isKind(of:)) {
                renderObfuscatedLabel(for: self, in: context)
            } else if swiftUIImageLayerTypes.contains(where: layer.isKind(of:)) {
                // renderBlurred(view: self)
                renderPixellated(view: self)
            } else if let imageView = self as? UIImageView {
                renderPixellated(view: imageView)
            } else if let vc = findViewController() as? SFSafariViewController {
                renderObfuscatedRemoteView(text: "SFSafariView", for: vc.view, in: context)
            } else if let webView = self as? WKWebView {
                renderObfuscatedRemoteView(text: "WKWebView", for: webView, in: context)
            } else if let view = self as? UITextView {
                renderObfuscatedLabel(for: view, in: context)
            } else if let view = self as? UITextField {
                renderObfuscatedLabel(for: view, in: context)
            } else if let label = self as? UILabel {
                renderObfuscatedLabel(for: label, in: context)
            } else {
                // Render the view
                renderInContext(context)
            }

            context.restoreGState()

            context.saveGState()

            let cornerPath = UIBezierPath(
                roundedRect: globalFrame,
                byRoundingCorners: layer.maskedCorners.toUIRectCorner,
                cornerRadii: CGSize(
                    width: layer.cornerRadius,
                    height: layer.cornerRadius
                )
            ).cgPath
            context.addPath(cornerPath)
            context.clip()

            for subview in subviews {
                guard !subview.isHidden, subview.alpha > 0 else { continue }
                subview.drawHierarchyWithMasking(in: context)
            }
            context.restoreGState()
        }

        /// Helper method to render a single view into a CGContext
        /// - Parameter context: The `CGContext` to render into.
        private func renderInContext(_ context: CGContext) {
            if let visualEffectsView = self as? UIVisualEffectView {
                renderVisualEffectView(visualEffectsView, in: context)
            } else if subviews.count == 0 {
                layer.render(in: context)
            } else {
                drawWithEffects(in: context)
            }
        }

        /// Renders the view hierarchy into an image, replacing `UITextField` and `UITextView` with obfuscated labels.
        /// - Returns: A `UIImage` representation of the view hierarchy.
        func renderWithMasking() -> UIImage? {
            // Start a graphics context with the view's size
            UIGraphicsBeginImageContextWithOptions(bounds.size, false, 0)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return nil
            }

            // Render view hierarchy
            drawHierarchyWithMasking(in: context)

            // Capture the rendered image
            let renderedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return renderedImage
        }

        /// Renders an obfuscated label (e.g., "****") in place of a text input view.
        /// - Parameters:
        ///   - view: The text input view to replace.
        ///   - context: The graphics context to render into.
        private func renderObfuscatedLabel(for view: UIView, in context: CGContext) {
            func maxCharacters(for frameWidth: CGFloat, using font: UIFont) -> Int {
                // Create a sample character to measure its size
                let sampleText = "*" // "W" tends to be one of the widest characters
                let sampleSize = sampleText.size(withAttributes: [.font: font])

                // Calculate how many of these characters can fit in the frame
                let maxCharacters = Int(frameWidth / sampleSize.width)
                return maxCharacters
            }

            let label = UILabel(frame: view.bounds)
            label.text = String(repeating: "*", count: maxCharacters(for: view.bounds.width, using: .preferredFont(forTextStyle: .body)))
            // label.textAlignment = .left
            label.lineBreakMode = .byClipping

            if let textField = view as? UITextField {
                label.text = (textField.text ?? textField.attributedText?.string)?.mask()
                label.textAlignment = textField.textAlignment
                label.font = textField.font
                label.textColor = textField.textColor
            } else if let textView = view as? UITextView {
                label.text = (textView.text ?? textView.attributedText.string)?.mask()
                label.textAlignment = textView.textAlignment
                label.font = textView.font
                label.textColor = textView.textColor
            } else if let labelView = view as? UILabel {
                label.text = (labelView.text ?? labelView.attributedText?.string)?.mask()
                label.textAlignment = labelView.textAlignment
                label.font = labelView.font
                label.textColor = labelView.textColor
            }

            label.backgroundColor = view.backgroundColor?.resolvedColor(with: view.traitCollection) ?? .clear

            // Render the label as a replacement
            label.layer.render(in: context)
        }

        private func renderObfuscatedRemoteView(text: String, for view: UIView, in _: CGContext) {
            guard let backgroundImage = UIGraphicsGetImageFromCurrentImageContext() else {
                return
            }
            let blurredBackground = applyGaussianBlur(to: backgroundImage, radius: 8)
            blurredBackground.draw(in: view.bounds)

            let overlayColor = UIColor.black.withAlphaComponent(0.6)
            overlayColor.setFill()
            UIRectFillUsingBlendMode(CGRect(origin: .zero, size: view.bounds.size), .normal)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.white,
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (view.bounds.width - textSize.width) / 2,
                y: (view.bounds.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }

        private func renderBlurred(view: UIView) {
            UIGraphicsBeginImageContextWithOptions(view.bounds.size, false, 0)
            guard let blurContext = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            view.layer.render(in: blurContext)
            guard let viewImage = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                return
            }
            let blurredImage = applyGaussianBlur(to: viewImage, radius: 10)
            UIGraphicsEndImageContext()
            blurredImage.draw(in: view.bounds)
        }

        private func renderPixellated(view: UIView) {
            UIGraphicsBeginImageContextWithOptions(view.bounds.size, false, 0)
            guard let blurContext = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            // view.layer.render(in: blurContext)
            guard let viewImage = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                return
            }
            let obfuscatedImage =
                applyGaussianBlur(
                    to: pixellate(
                        image: viewImage,
                        scale: Float(viewImage.size.width) / 5.0
                    ),
                    radius: 4
                )

            UIGraphicsEndImageContext()
            obfuscatedImage.draw(in: view.bounds)
        }

        /// Custom drawing function that renders the layer, including corner radius and effects.
        /// - Parameter context: The `CGContext` to draw into.
        func drawWithEffects(in context: CGContext) {
            context.saveGState() // Save the initial graphics state

            // Draw the background color
            if let backgroundColor = layer.backgroundColor ?? backgroundColor?.cgColor {
                context.setFillColor(backgroundColor)
                context.fill(bounds)
            }

            // Handle the layer mask if present
            if let mask = layer.mask {
                context.saveGState()
                if let maskContext = UIGraphicsGetCurrentContext() {
                    mask.render(in: maskContext) // Render the mask into the current context
                }
                context.restoreGState()
            }

            // Check if this is a UIVisualEffectView and handle accordingly
            if let visualEffectsView = self as? UIVisualEffectView {
                renderVisualEffectView(visualEffectsView, in: context)
            } else {
                layer.draw(in: context) // Fallback to default layer drawing
            }

            // Draw shadow (if any)
            if layer.shadowOpacity > 0 {
                context.setShadow(
                    offset: layer.shadowOffset,
                    blur: layer.shadowRadius,
                    color: layer.shadowColor
                )
            }

            context.restoreGState() // Restore the graphics state
        }

        private func renderVisualEffectView(_ visualEffectView: UIVisualEffectView, in context: CGContext) {
            // Retrieve the background color from ancestors, if available
            guard let backgroundColor = visualEffectView.ancestors.first(where: { $0.layer.backgroundColor != nil })?.layer.backgroundColor else {
                return
            }

            // Capture the current graphics context as an image
            guard let backgroundImage = UIGraphicsGetImageFromCurrentImageContext() else { return }
            guard let cgImage = backgroundImage.cgImage else { return }

            // Convert visualEffectView's frame to a rect in the image's coordinate space
            let cropRect = visualEffectView.convert(visualEffectView.bounds, to: nil)
            let scaledCropRect = CGRect(
                x: cropRect.origin.x * backgroundImage.scale,
                y: cropRect.origin.y * backgroundImage.scale,
                width: cropRect.width * backgroundImage.scale,
                height: cropRect.height * backgroundImage.scale
            )

            // Crop the image
            guard let croppedCGImage = cgImage.cropping(to: scaledCropRect) else { return }
            let croppedImage = UIImage(cgImage: croppedCGImage)

            // Optional: Apply a Gaussian blur or other effects here
            let blurredImage = applyBokehBlur(to: croppedImage, radius: 15)

            // Draw the resulting image in the graphics context
            context.saveGState()
            context.translateBy(x: 0, y: visualEffectView.bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.clip(to: visualEffectView.bounds)
            context.concatenate(visualEffectView.transform)
            context.draw(blurredImage.cgImage!, in: visualEffectView.bounds)
            let fillColor = visualEffectView.traitCollection.userInterfaceStyle == .light ? UIColor.white : UIColor.black
            fillColor.withAlphaComponent(0.9).setFill()
            UIRectFillUsingBlendMode(visualEffectView.bounds, .normal)
            context.restoreGState()
        }

        func findViewController() -> UIViewController? {
            var responder: UIResponder? = self

            while responder != nil {
                if let responder = responder as? UIViewController {
                    return responder
                }
                responder = responder?.next
            }
            return nil
        }

        /// Applies a Gaussian blur to an image.
        /// - Parameter image: The image to blur.
        /// - Returns: A new UIImage with the blur effect applied.
        private func applyGaussianBlur(to image: UIImage, radius: Float) -> UIImage {
            let context = CIContext()
            let inputImage = CIImage(image: image)
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = inputImage
            filter.radius = radius

            guard
                let outputImage = filter.outputImage,
                let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
            else {
                return image
            }
            return UIImage(cgImage: cgImage)
        }

        private func applyBokehBlur(to image: UIImage, radius: Float) -> UIImage {
            let context = CIContext()
            let inputImage = CIImage(image: image)
            let filter = CIFilter.bokehBlur()
            filter.inputImage = inputImage
            filter.radius = radius

            guard
                let outputImage = filter.outputImage,
                let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
            else {
                return image
            }
            return UIImage(cgImage: cgImage)
        }

        private func pixellate(image: UIImage, scale: Float) -> UIImage {
            let context = CIContext()
            let inputImage = CIImage(image: image)
            let filter = CIFilter.pixellate()
            filter.inputImage = inputImage
            filter.scale = scale

            guard
                let outputImage = filter.outputImage,
                let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
            else {
                return image
            }
            return UIImage(cgImage: cgImage)
        }
    }

    extension CACornerMask {
        /// Converts `CACornerMask` to the equivalent `UIRectCorner`.
        var toUIRectCorner: UIRectCorner {
            var rectCorner: UIRectCorner = []
            if contains(.layerMinXMinYCorner) {
                rectCorner.insert(.topLeft)
            }
            if contains(.layerMaxXMinYCorner) {
                rectCorner.insert(.topRight)
            }
            if contains(.layerMinXMaxYCorner) {
                rectCorner.insert(.bottomLeft)
            }
            if contains(.layerMaxXMaxYCorner) {
                rectCorner.insert(.bottomRight)
            }
            return rectCorner
        }
    }

    #if TESTING
        extension PostHogReplayIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
            }
        }
    #endif

#endif

// swiftlint:enable cyclomatic_complexity
