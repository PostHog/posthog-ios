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

    /// Cached snapshot of session replay config flags, read once per snapshot cycle
    /// to avoid repeated weak-ref + optional-chain traversals during recursive view tree walks.
    struct ReplayMaskConfig {
        let maskAllTextInputs: Bool
        let maskAllImages: Bool
        let maskAllSandboxedViews: Bool

        init(from config: PostHogConfig?) {
            maskAllTextInputs = config?.sessionReplayConfig.maskAllTextInputs ?? true
            maskAllImages = config?.sessionReplayConfig.maskAllImages ?? true
            maskAllSandboxedViews = config?.sessionReplayConfig.maskAllSandboxedViews ?? true
        }
    }

    class PostHogReplayIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private var config: PostHogConfig? {
            postHog?.config
        }

        private weak var postHog: PostHogSDK?

        private var isEnabled: Bool = false

        private let windowViewsLock = NSLock()
        private let windowViews = NSMapTable<UIWindow, ViewTreeSnapshotStatus>.weakToStrongObjects()
        private let installedPluginsLock = NSLock()
        private var applicationEventToken: RegistrationToken?
        private var applicationBackgroundedToken: RegistrationToken?
        private var applicationForegroundedToken: RegistrationToken?
        private var viewLayoutToken: RegistrationToken?
        private var remoteConfigLoadedToken: RegistrationToken?
        private var sessionIdChangedToken: RegistrationToken?
        private var eventCapturedToken: RegistrationToken?
        private var installedPlugins: [PostHogSessionReplayPlugin] = []

        private let eventTriggersLock = NSLock()
        private var eventTriggers: [String]?
        private var triggerActivatedSessionId: String?

        /**
         ### Mapping of SwiftUI Views to UIKit (up until iOS 18)

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

         ### Mapping of SwiftUI Views to UIKit (iOS 26)

         Starting on iOS 26 (Xcode 26 SwiftUI rendering engine), some SwiftUI primitives can be drawn
         without a dedicated backing `UIView` and may instead appear as `CALayer` sublayers of parent
         views.

         Observed additions/changes with iOS 26:
         - Text / Button drawing may appear as the sublayer class `_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer`.
         - Image and AsyncImage appear as sublayer class `SwiftUI.ImageLayer` (instead of a host view).
         - `TextField` and `SecureTextField` are not affected by this change and still map to `UITextField`
         - `TextEditor` is not affected by this change and still maps to `UITextView`
         */

        /// `AsyncImage` and `Image`
        private let swiftUIImageLayerTypes = [
            "SwiftUI.ImageLayer",
        ].compactMap(NSClassFromString)

        /// `Text`, `Button`, `TextEditor` views
        private let swiftUITextBasedViewTypes = [
            "_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer", // Text, Button (iOS 26+)
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
            "_TtC7SwiftUIP33_E19F490D25D5E0EC8A24903AF958E34115ColorShapeLayer", // Solid-color filled shapes (Circle, Rectangle, SF Symbols etc.)
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

            // Resolve event triggers from cached remote config (if available)
            if let cachedRemoteConfig = postHog.remoteConfig?.getRemoteConfig() {
                updateEventTriggers(from: cachedRemoteConfig)
            }

            // Subscribe to remote config changes (needed before start to update triggers)
            remoteConfigLoadedToken = postHog.remoteConfig?.onRemoteConfigLoaded.subscribe { [weak self] config in
                self?.applyRemoteConfig(remoteConfig: config)
            }

            // Subscribe to event captures for trigger matching (needed before start to detect triggers)
            eventCapturedToken = postHog.onEventCaptured.subscribe { [weak self] event in
                self?.handleEventCaptured(event: event.event)
            }

            start()
        }

        func uninstall(_ postHog: PostHogSDK) {
            if self.postHog === postHog || self.postHog == nil {
                stop()
                // Clear the pre-start listeners
                remoteConfigLoadedToken = nil
                eventCapturedToken = nil
                self.postHog = nil
                PostHogReplayIntegration.integrationInstalledLock.withLock {
                    PostHogReplayIntegration.integrationInstalled = false
                }
            }
        }

        /// Returns true if event triggers are configured and the current session has not been activated yet.
        private func shouldWaitForEventTriggers() -> Bool {
            guard let postHog else { return false }

            guard let currentSessionId = postHog.sessionManager.getSessionId(readOnly: true) else {
                return false
            }

            let (triggers, activatedSession) = eventTriggersLock.withLock {
                (eventTriggers, triggerActivatedSessionId)
            }

            guard let triggers = triggers, !triggers.isEmpty else {
                return false
            }

            // Wait if this session has not been activated yet
            return activatedSession != currentSessionId
        }

        /// Starts session replay recording.
        func start() {
            guard let postHog, !isEnabled else { return }

            // Check if we should wait for event triggers before starting
            if shouldWaitForEventTriggers() {
                let triggers = eventTriggersLock.withLock { eventTriggers } ?? []
                hedgeLog("[Session Replay] Event triggers configured. Integration will not start until any of these events are captured: \(triggers)")
                return
            }

            // Check sampling before starting timers and listeners
            if let sessionId = postHog.sessionManager.getSessionId(readOnly: true),
               !shouldRecordSession(postHog: postHog, sessionId: sessionId)
            {
                hedgeLog("[Session Replay] Session \(sessionId) not sampled for recording. Skipping start.")
                return
            }

            isEnabled = true
            // Listen for session changes to stop recording when a new session starts (if triggers are configured)
            sessionIdChangedToken = postHog.sessionManager.onSessionIdChanged.subscribe { [weak self] in
                self?.handleSessionChanged()
            }

            // flutter captures snapshots, so we don't need to capture them here
            if isNotFlutter() {
                let interval = postHog.config.sessionReplayConfig.throttleDelay
                viewLayoutToken = DI.main.viewLayoutPublisher.onViewLayout.subscribe(throttle: interval) { [weak self] in
                    // called on main thread
                    self?.snapshot()
                }
            }

            // start listening to `UIApplication.sendEvent`
            let applicationEventPublisher = DI.main.applicationEventPublisher
            applicationEventToken = applicationEventPublisher.onApplicationEvent.subscribe { [weak self] event, date in
                self?.handleApplicationEvent(event: event, date: date)
            }

            // Install plugins
            let pluginTypes = postHog.config.sessionReplayConfig.getPluginTypes()
            let remoteConfig = postHog.remoteConfig?.getRemoteConfig()
            let pluginsToStart = installedPluginsLock.withLock {
                installedPlugins = []
                for pluginType in pluginTypes {
                    if !pluginType.isEnabledRemotely(remoteConfig: remoteConfig) {
                        hedgeLog("[Session Replay] Plugin \(pluginType) skipped - disabled by cached remote config")
                        continue
                    }
                    let plugin = pluginType.init()
                    installedPlugins.append(plugin)
                }
                return installedPlugins
            }

            for plugin in pluginsToStart {
                plugin.start(postHog: postHog)
            }

            // Start listening to application background events and pause all plugins
            let applicationLifecyclePublisher = DI.main.appLifecyclePublisher
            applicationBackgroundedToken = applicationLifecyclePublisher.onDidEnterBackground.subscribe { [weak self] in
                self?.pauseAllPlugins()
            }

            // Start listening to application foreground events and resume all plugins
            applicationForegroundedToken = applicationLifecyclePublisher.onDidBecomeActive.subscribe { [weak self] in
                self?.resumeAllPlugins()
            }

            hedgeLog("Session replay recording started.")
        }

        /// Stops session replay recording.
        /// Note: This does not clear remoteConfigLoadedToken or eventCapturedToken as those are managed by install/uninstall.
        func stop() {
            guard isEnabled else { return }
            isEnabled = false
            resetViews()
            sessionIdChangedToken = nil

            // stop listening to `UIApplication.sendEvent`
            applicationEventToken = nil
            // stop listening to Application lifecycle events
            applicationBackgroundedToken = nil
            applicationForegroundedToken = nil
            // stop listening to `UIView.layoutSubviews` events
            viewLayoutToken = nil
            // stop plugins
            let pluginsToStop = installedPluginsLock.withLock {
                defer { installedPlugins = [] }
                return installedPlugins
            }

            for plugin in pluginsToStop {
                plugin.stop()
            }

            hedgeLog("Session replay recording stopped.")
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

        /// Determines whether the given session should be recorded based on sample rate configuration.
        /// Local config sample rate takes precedence over remote config.
        /// Returns `true` if no sample rate is configured (record everything).
        private func shouldRecordSession(postHog: PostHogSDK, sessionId: String) -> Bool {
            let localSampleRate = postHog.config.sessionReplayConfig.sampleRate?.doubleValue
            let remoteSampleRate = postHog.remoteConfig?.getRecordingSampleRate()

            guard let sampleRate = localSampleRate ?? remoteSampleRate else {
                return true
            }

            return sampleOnProperty(sessionId, sampleRate)
        }

        private func reevaluateSampling() {
            guard let postHog else { return }

            guard let sessionId = postHog.sessionManager.getSessionId(readOnly: true) else {
                return
            }

            let sampled = shouldRecordSession(postHog: postHog, sessionId: sessionId)

            if sampled, !isEnabled {
                hedgeLog("[Session Replay] Session \(sessionId) sampled for recording. Starting.")
                start()
            } else if !sampled, isEnabled {
                hedgeLog("[Session Replay] Session \(sessionId) not sampled for recording. Stopping.")
                stop()
            }
        }

        /// Called when session ID changes. Handles view reset, sampling re-evaluation,
        /// and trigger state management.
        private func handleSessionChanged() {
            guard let postHog else { return }

            guard let currentSessionId = postHog.sessionManager.getSessionId(readOnly: true) else {
                return
            }

            // Always reset views on session change
            if isEnabled {
                resetViews()
            }

            let (triggers, activatedSession) = eventTriggersLock.withLock {
                (eventTriggers, triggerActivatedSessionId)
            }

            // If triggers are configured and this session hasn't been activated, stop the integration
            if let triggers = triggers, !triggers.isEmpty, activatedSession != currentSessionId {
                if isEnabled {
                    hedgeLog("[Session Replay] New session \(currentSessionId), stopping until event trigger is matched")
                    stop()
                }
                return
            }

            // Re-evaluate sampling for the new session
            reevaluateSampling()
        }

        private func pauseAllPlugins() {
            let pluginsToPause = installedPluginsLock.withLock { installedPlugins }
            for plugin in pluginsToPause {
                plugin.pause()
            }
        }

        private func resumeAllPlugins() {
            let pluginsToResume = installedPluginsLock.withLock { installedPlugins }
            for plugin in pluginsToResume {
                plugin.resume()
            }
        }

        func applyRemoteConfig(remoteConfig: [String: Any]?) {
            updatePlugins(from: remoteConfig)
            updateEventTriggers(from: remoteConfig)
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

            // capture necessary touch information on the main thread before performing any asynchronous operations
            // - this ensures that UITouch associated objects like UIView, UIWindow, or [UIGestureRecognizer] are still valid.
            // - these objects may be released or erased by the system if accessed asynchronously, resulting in invalid/zeroed-out touch coordinates
            // Only capture began/ended phases — other phases (moved, stationary, cancelled) are ignored
            let touchInfo = touches.compactMap { touch -> (phase: UITouch.Phase, location: CGPoint)? in
                let phase = touch.phase
                guard phase == .began || phase == .ended else { return nil }
                return (phase: phase, location: touch.location(in: window))
            }

            PostHogReplayIntegration.dispatchQueue.async { [touchInfo, weak postHog = postHog] in
                // always make sure we have a fresh session id as early as possible
                guard let sessionId = postHog?.sessionManager.getSessionId(at: date) else {
                    return
                }

                // captured weakly since integration may have uninstalled by now
                guard let postHog else { return }

                var snapshotsData: [Any] = []
                // touchInfo already filtered to only .began and .ended phases
                let timestamp = date.toMillis()
                for touch in touchInfo {
                    let type: Int = touch.phase == .began ? 7 : 9

                    guard touch.location != .zero else {
                        continue
                    }

                    let posX = touch.location.x.toInt() ?? 0
                    let posY = touch.location.y.toInt() ?? 0

                    // if the id is 0, BE transformer will set it to the virtual bodyId
                    let touchData: [String: Any] = ["id": 0, "pointerType": 2, "source": 2, "type": type, "x": posX, "y": posY]

                    let data: [String: Any] = ["type": 3, "data": touchData, "timestamp": timestamp]
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
            guard let wireframe = postHog.config.sessionReplayConfig.screenshotMode ? toScreenshotWireframe(window) : toWireframe(window) else {
                return
            }

            // Capture timestamp and window size on main thread, but defer all other work
            let timestampDate = Date()
            let timestamp = timestampDate.toMillis()
            let windowSize = window.bounds.size

            // Move lock access, meta event creation, and dict building off the main thread
            PostHogReplayIntegration.dispatchQueue.async { [weak self] in
                guard let self else { return }

                // always make sure we have a fresh session id at correct timestamp
                guard let sessionId = postHog.sessionManager.getSessionId(at: timestampDate) else {
                    return
                }

                var snapshotsData: [Any] = []

                // Check and emit meta event (lock access moved off main thread)
                let snapshotStatus = self.windowViewsLock.withLock {
                    self.windowViews.object(forKey: window) ?? ViewTreeSnapshotStatus()
                }

                if !snapshotStatus.sentMetaEvent {
                    let width = windowSize.width.toInt() ?? 0
                    let height = windowSize.height.toInt() ?? 0

                    var data: [String: Any] = ["width": width, "height": height]

                    if let screenName = screenName {
                        data["href"] = screenName
                    }

                    let metaData: [String: Any] = ["type": 4, "data": data, "timestamp": timestamp]
                    snapshotsData.append(metaData)
                    snapshotStatus.sentMetaEvent = true

                    self.windowViewsLock.withLock {
                        self.windowViews.setObject(snapshotStatus, forKey: window)
                    }
                }

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
            wireframe.posX = frame.origin.x.toInt() ?? 0
            wireframe.posY = frame.origin.y.toInt() ?? 0
            wireframe.width = frame.size.width.toInt() ?? 0
            wireframe.height = frame.size.height.toInt() ?? 0

            return wireframe
        }

        private func findMaskableWidgets(_ view: UIView, _ window: UIWindow, _ maskableWidgets: inout [CGRect], _ maskChildren: inout Bool) {
            let maskConfig = ReplayMaskConfig(from: config)
            findMaskableWidgets(view, window, &maskableWidgets, &maskChildren, maskConfig)
        }

        private func findMaskableWidgets(_ view: UIView, _ window: UIWindow, _ maskableWidgets: inout [CGRect], _ maskChildren: inout Bool, _ maskConfig: ReplayMaskConfig) {
            // Fast path: container types (plain UIView, UIWindow) that can't contain sensitive content.
            // Check type BEFORE postHogNoMask to avoid associated object lookup for containers.
            let isPlainUIView = type(of: view) == UIView.self || view is UIWindow
            if isPlainUIView {
                // Still check no-mask and manual masking for tagged views
                if view.postHogNoMask {
                    return
                }
                if view.postHogNoCapture {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
                // Check cheap boolean first to short-circuit expensive isNoCapture() call
                if maskChildren || view.isNoCapture() {
                    let viewRect = view.toAbsoluteRect(window)
                    if !viewRect.equalTo(window.frame) {
                        maskableWidgets.append(viewRect)
                    } else {
                        maskChildren = true
                    }
                }
                // Recurse into children
                if !view.subviews.isEmpty {
                    for child in view.subviews {
                        if !child.isVisible() {
                            continue
                        }
                        findMaskableWidgets(child, window, &maskableWidgets, &maskChildren, maskConfig)
                    }
                }
                maskChildren = false
                return
            }

            // User explicitly marked this view (and its subviews) as non-maskable
            if view.postHogNoMask {
                return
            }

            // UIKit type checks — if-else chain ensures only one type cast succeeds.
            // Views that don't match any known UIKit type fall through to SwiftUI/RN checks below.
            if let textView = view as? UITextView {
                if isTextViewSensitive(textView, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if let textField = view as? UITextField {
                if isTextFieldSensitive(textField, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if let image = view as? UIImageView {
                if isImageViewSensitive(image, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if let label = view as? UILabel {
                if isLabelSensitive(label, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if let button = view as? UIButton {
                if isButtonSensitive(button, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if let webView = view as? WKWebView {
                if isAnyInputSensitive(webView, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if let theSwitch = view as? UISwitch {
                if isSwitchSensitive(theSwitch, maskConfig) {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if view is UIPickerView {
                if isTextInputSensitive(view, maskConfig), view.subviews.isEmpty {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }
            } else if !(view is UIScrollView || view is UITableViewCell || view is UICollectionViewCell) {
                // Not a known UIKit type — check React Native and SwiftUI types

                // React Native checks (only when RN classes are loaded)
                if let reactNativeTextView = reactNativeTextView,
                   view.isKind(of: reactNativeTextView), maskConfig.maskAllTextInputs
                {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }

                if let reactNativeImageView = reactNativeImageView,
                   view.isKind(of: reactNativeImageView), maskConfig.maskAllImages
                {
                    maskableWidgets.append(view.toAbsoluteRect(window))
                    return
                }

                let hasSubViews = !view.subviews.isEmpty

                /// SwiftUI: Text based views like `Text`, `Button`, `TextEditor`
                if swiftUITextBasedViewTypes.contains(where: view.isKind(of:)) {
                    if isTextInputSensitive(view, maskConfig), !hasSubViews {
                        maskableWidgets.append(view.toAbsoluteRect(window))
                        return
                    }
                }

                /// SwiftUI: Image based views like `Image`, `AsyncImage`
                if swiftUIImageLayerTypes.contains(where: view.layer.isKind(of:)) {
                    if isSwiftUIImageSensitive(view, maskConfig), !hasSubViews {
                        maskableWidgets.append(view.toAbsoluteRect(window))
                        return
                    }
                }

                // SwiftUI iOS 26 (new SwiftUI rendering engine in Xcode 26)
                if #available(iOS 26.0, *) {
                    findMaskableLayers(view.layer, view, window, &maskableWidgets, maskConfig)
                }

                // this can be anything, so better to be conservative
                if swiftUIGenericTypes.contains(where: { view.isKind(of: $0) }), !isSwiftUILayerSafe(view.layer) {
                    if isTextInputSensitive(view, maskConfig), !hasSubViews {
                        maskableWidgets.append(view.toAbsoluteRect(window))
                        return
                    }
                }
            }

            // detect any views that don't belong to the current process (likely system views)
            if maskConfig.maskAllSandboxedViews,
               let systemSandboxedView,
               view.isKind(of: systemSandboxedView)
            {
                maskableWidgets.append(view.toAbsoluteRect(window))
                return
            }

            // manually masked views through `.postHogMask()` view modifier
            if view.postHogNoCapture {
                maskableWidgets.append(view.toAbsoluteRect(window))
                return
            }

            // on RN, lots get converted to RCTRootContentView, RCTRootView, RCTView and sometimes its just the whole screen, we dont want to mask
            // in such cases
            if maskChildren || view.isNoCapture() {
                let viewRect = view.toAbsoluteRect(window)
                let windowRect = window.frame

                // Check if the rectangles do not match
                if !viewRect.equalTo(windowRect) {
                    maskableWidgets.append(viewRect)
                } else {
                    maskChildren = true
                }
            }

            if !view.subviews.isEmpty {
                for child in view.subviews {
                    if !child.isVisible() {
                        continue
                    }

                    findMaskableWidgets(child, window, &maskableWidgets, &maskChildren, maskConfig)
                }
            }
            maskChildren = false
        }

        /// Recursively iterate through layer hierarchy to find maskable layers (iOS 26+)
        ///
        /// On iOS 26, SwiftUI primitives (Text, Image, Button) are rendered as CALayer sublayers
        /// of parent views rather than having their own backing UIView. When `.postHogMask()` is applied,
        /// the flag is set directly on the CALayers via the PostHogTagViewModifier.
        @available(iOS 26.0, *)
        private func findMaskableLayers(_ layer: CALayer, _ view: UIView, _ window: UIWindow, _ maskableWidgets: inout [CGRect], _ maskConfig: ReplayMaskConfig) {
            for sublayer in layer.sublayers ?? [] {
                // Skip layers tagged with .postHogNoMask()
                if sublayer.postHogNoMask {
                    continue
                }

                // Check if layer is manually tagged with .postHogMask()
                if sublayer.postHogNoCapture {
                    maskableWidgets.append(sublayer.toAbsoluteRect(window))
                    continue
                }

                // Text-based layers
                if swiftUITextBasedViewTypes.contains(where: sublayer.isKind(of:)) {
                    if isTextInputSensitive(view, maskConfig) {
                        maskableWidgets.append(sublayer.toAbsoluteRect(window))
                    }
                }

                // Image layers
                if swiftUIImageLayerTypes.contains(where: sublayer.isKind(of:)) {
                    if isSwiftUIImageSensitive(view, maskConfig) {
                        maskableWidgets.append(sublayer.toAbsoluteRect(window))
                    }
                }

                // Recursively check sublayers
                if let sublayers = sublayer.sublayers, !sublayers.isEmpty {
                    findMaskableLayers(sublayer, view, window, &maskableWidgets, maskConfig)
                }
            }
        }

        private func toScreenshotWireframe(_ window: UIWindow) -> RRWireframe? {
            // this will bail on view controller animations (interactive or not)
            if !window.isVisible() || isAnimatingTransition(window) {
                return nil
            }

            var maskableWidgets: [CGRect] = []
            var maskChildren = false
            let maskConfig = ReplayMaskConfig(from: config)
            findMaskableWidgets(window, window, &maskableWidgets, &maskChildren, maskConfig)

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

        private func isAnyInputSensitive(_ view: UIView, _ maskConfig: ReplayMaskConfig) -> Bool {
            isTextInputSensitive(view, maskConfig) || maskConfig.maskAllImages
        }

        private func isTextInputSensitive(_ view: UIView) -> Bool {
            config?.sessionReplayConfig.maskAllTextInputs == true || view.isNoCapture()
        }

        private func isTextInputSensitive(_ view: UIView, _ maskConfig: ReplayMaskConfig) -> Bool {
            maskConfig.maskAllTextInputs || view.isNoCapture()
        }

        private func isLabelSensitive(_ view: UILabel) -> Bool {
            isTextInputSensitive(view) && hasText(view.text)
        }

        private func isLabelSensitive(_ view: UILabel, _ maskConfig: ReplayMaskConfig) -> Bool {
            isTextInputSensitive(view, maskConfig) && hasText(view.text)
        }

        private func isButtonSensitive(_ view: UIButton) -> Bool {
            isTextInputSensitive(view) && hasText(view.titleLabel?.text)
        }

        private func isButtonSensitive(_ view: UIButton, _ maskConfig: ReplayMaskConfig) -> Bool {
            isTextInputSensitive(view, maskConfig) && hasText(view.titleLabel?.text)
        }

        private func isTextViewSensitive(_ view: UITextView) -> Bool {
            (isTextInputSensitive(view) || view.isSensitiveText()) && hasText(view.text)
        }

        private func isTextViewSensitive(_ view: UITextView, _ maskConfig: ReplayMaskConfig) -> Bool {
            (isTextInputSensitive(view, maskConfig) || view.isSensitiveText()) && hasText(view.text)
        }

        private func isSwitchSensitive(_ view: UISwitch) -> Bool {
            var containsText = true
            if #available(iOS 14.0, *) {
                containsText = hasText(view.title)
            }

            return isTextInputSensitive(view) && containsText
        }

        private func isSwitchSensitive(_ view: UISwitch, _ maskConfig: ReplayMaskConfig) -> Bool {
            var containsText = true
            if #available(iOS 14.0, *) {
                containsText = hasText(view.title)
            }

            return isTextInputSensitive(view, maskConfig) && containsText
        }

        private func isTextFieldSensitive(_ view: UITextField) -> Bool {
            (isTextInputSensitive(view) || view.isSensitiveText()) && (hasText(view.text) || hasText(view.placeholder))
        }

        private func isTextFieldSensitive(_ view: UITextField, _ maskConfig: ReplayMaskConfig) -> Bool {
            (isTextInputSensitive(view, maskConfig) || view.isSensitiveText()) && (hasText(view.text) || hasText(view.placeholder))
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

        private func isSwiftUIImageSensitive(_ view: UIView, _ maskConfig: ReplayMaskConfig) -> Bool {
            maskConfig.maskAllImages || view.isNoCapture()
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

        private func isImageViewSensitive(_ view: UIImageView, _ maskConfig: ReplayMaskConfig) -> Bool {
            guard let image = view.image else { return false }

            if view.isNoCapture() {
                return true
            }

            if isAssetsImage(image) {
                return false
            }

            if image.isSymbolImage {
                return false
            }

            return maskConfig.maskAllImages
        }

        private func toWireframe(_ view: UIView) -> RRWireframe? {
            if !view.isVisible() {
                return nil
            }

            let wireframe = createBasicWireframe(view)

            let style = RRStyle()

            // Use if-else chain to avoid unnecessary type casts once a type is matched
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
            } else if let textField = view as? UITextField {
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
            } else if view is UIPickerView {
                wireframe.type = "input"
                wireframe.inputType = "select"
                // set wireframe.value from selected row
            } else if let theSwitch = view as? UISwitch {
                wireframe.type = "input"
                wireframe.inputType = "toggle"
                wireframe.checked = theSwitch.isOn
                if #available(iOS 14.0, *) {
                    if let text = theSwitch.title {
                        wireframe.label = isSwitchSensitive(theSwitch) ? text.mask() : text
                    }
                }
            } else if let imageView = view as? UIImageView {
                wireframe.type = "image"
                if let image = imageView.image {
                    if !isImageViewSensitive(imageView) {
                        wireframe.image = image
                    }
                }
            } else if let button = view as? UIButton {
                wireframe.type = "input"
                wireframe.inputType = "button"
                wireframe.disabled = !button.isEnabled

                if let text = button.titleLabel?.text {
                    wireframe.value = isButtonSensitive(button) ? text.mask() : text
                }
            } else if let label = view as? UILabel {
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
            } else if view is WKWebView {
                wireframe.type = "web_view"
            } else if let progressView = view as? UIProgressView {
                wireframe.type = "input"
                wireframe.inputType = "progress"
                wireframe.value = progressView.progress
                wireframe.max = 1
                style.bar = "horizontal"
            } else if view is UIActivityIndicatorView {
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

        private func handleEventCaptured(event: String) {
            guard let postHog else { return }

            guard let currentSessionId = postHog.sessionManager.getSessionId(readOnly: true) else {
                return
            }

            let (triggers, activatedSession) = eventTriggersLock.withLock {
                (eventTriggers, triggerActivatedSessionId)
            }

            guard let triggers = triggers, !triggers.isEmpty else {
                return
            }

            // Check if this session has already been activated
            guard activatedSession != currentSessionId else {
                return
            }

            if triggers.contains(event) {
                eventTriggersLock.withLock {
                    triggerActivatedSessionId = currentSessionId
                }
                hedgeLog("[Session Replay] Event trigger matched: \(event). Starting replay for session \(currentSessionId).")
                // Start the integration now that a trigger has matched
                start()
            }
        }

        /// Resolves event triggers from remote config payload.
        private func updateEventTriggers(from remoteConfig: [String: Any]?) {
            // Parse event triggers from remote config
            // Path: sessionRecording.eventTriggers ([String])
            let remoteEventTriggers: [String]? = {
                guard let sessionRecording = remoteConfig?["sessionRecording"] as? [String: Any],
                      let triggers = sessionRecording["eventTriggers"] as? [String]
                else {
                    return nil
                }
                return triggers
            }()

            let previousTriggers = eventTriggersLock.withLock {
                let prev = eventTriggers
                eventTriggers = remoteEventTriggers
                // Clear activated session when triggers change
                triggerActivatedSessionId = nil
                return prev
            }

            // If triggers were added/changed and integration is running, stop it
            if let newTriggers = remoteEventTriggers, !newTriggers.isEmpty {
                if isEnabled {
                    hedgeLog("[Session Replay] Event triggers updated. Stopping until trigger is matched.")
                    stop()
                }
            } else if previousTriggers != nil, !previousTriggers!.isEmpty, remoteEventTriggers?.isEmpty != false {
                // Triggers were removed - start if not already running and sampling allows
                if !isEnabled {
                    hedgeLog("[Session Replay] Event triggers removed. Starting replay.")
                    start()
                }
            }
        }

        /// Updates plugin enablement based on remote config.
        private func updatePlugins(from remoteConfig: [String: Any]?) {
            guard let postHog else { return }

            let allPluginTypes = postHog.config.sessionReplayConfig.getPluginTypes()

            var pluginsToStop: [PostHogSessionReplayPlugin] = []
            var pluginsToStart: [PostHogSessionReplayPlugin] = []

            installedPluginsLock.withLock {
                for pluginType in allPluginTypes {
                    let isEnabled = pluginType.isEnabledRemotely(remoteConfig: remoteConfig)
                    let installedIndex = installedPlugins.firstIndex { type(of: $0) == pluginType }

                    if let index = installedIndex, !isEnabled {
                        // Installed, but disabled in remote
                        pluginsToStop.append(installedPlugins[index])
                        installedPlugins.remove(at: index)
                    } else if installedIndex == nil, isEnabled {
                        // Not installed, but enabled in remote
                        let plugin = pluginType.init()
                        installedPlugins.append(plugin)
                        pluginsToStart.append(plugin)
                    }
                }
            }

            for plugin in pluginsToStop {
                plugin.stop()
                hedgeLog("[Session Replay] Plugin \(type(of: plugin)) uninstalled - disabled by remote config")
            }
            for plugin in pluginsToStart {
                plugin.start(postHog: postHog)
                hedgeLog("[Session Replay] Plugin \(type(of: plugin)) installed - enabled by remote config")
            }
        }
    }

    private protocol AnyObjectUIHostingViewController: AnyObject {}

    extension UIHostingController: AnyObjectUIHostingViewController {}

    #if TESTING
        extension PostHogReplayIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
            }

            /// Benchmark: expose findMaskableWidgets for performance testing
            func benchmarkFindMaskableWidgets(_ window: UIWindow) -> [CGRect] {
                var maskableWidgets: [CGRect] = []
                var maskChildren = false
                findMaskableWidgets(window, window, &maskableWidgets, &maskChildren)
                return maskableWidgets
            }

            /// Benchmark: expose toWireframe for performance testing
            func benchmarkToWireframe(_ view: UIView) -> RRWireframe? {
                toWireframe(view)
            }

            /// Benchmark: expose toScreenshotWireframe for performance testing
            func benchmarkToScreenshotWireframe(_ window: UIWindow) -> RRWireframe? {
                toScreenshotWireframe(window)
            }

            /// Benchmark: expose createBasicWireframe for performance testing
            func benchmarkCreateBasicWireframe(_ view: UIView) -> RRWireframe {
                createBasicWireframe(view)
            }

            /// Creates a standalone instance for benchmarking (no PostHogSDK dependency)
            static func createForBenchmark(config _: PostHogConfig) -> PostHogReplayIntegration {
                return PostHogReplayIntegration()
            }
        }
    #endif

#endif

// swiftlint:enable cyclomatic_complexity
