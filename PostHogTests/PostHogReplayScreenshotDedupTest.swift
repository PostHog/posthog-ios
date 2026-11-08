#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing
    import UIKit

    @Suite("Screenshot mode unchanged-frame dedup")
    class PostHogReplayScreenshotDedupTests {
        struct DedupCase: CustomTestStringConvertible {
            let name: String
            let imageHash: Int?
            let lastImageHash: Int?
            let hasPendingSnapshotData: Bool
            let expectedSkip: Bool

            var testDescription: String { name }
        }

        @Test("Screenshot dedup decision", arguments: [
            DedupCase(
                name: "skips an unchanged image when no other snapshot data is pending",
                imageHash: 42, lastImageHash: 42, hasPendingSnapshotData: false, expectedSkip: true
            ),
            DedupCase(
                name: "sends a changed image",
                imageHash: 43, lastImageHash: 42, hasPendingSnapshotData: false, expectedSkip: false
            ),
            DedupCase(
                name: "never skips while a meta event (or other data) is pending",
                imageHash: 42, lastImageHash: 42, hasPendingSnapshotData: true, expectedSkip: false
            ),
            DedupCase(
                name: "never skips when there is no image hash",
                imageHash: nil, lastImageHash: 42, hasPendingSnapshotData: false, expectedSkip: false
            ),
            DedupCase(
                name: "sends the first image, when there is no previous hash",
                imageHash: 42, lastImageHash: nil, hasPendingSnapshotData: false, expectedSkip: false
            ),
        ])
        func screenshotDedupDecision(_ testCase: DedupCase) {
            let skip = PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: testCase.imageHash,
                lastImageHash: testCase.lastImageHash,
                hasPendingSnapshotData: testCase.hasPendingSnapshotData
            )
            #expect(skip == testCase.expectedSkip)
        }
    }

    @Suite("Unchanged-frame backoff")
    class PostHogReplayFrameBackoffTests {
        private func frame(_ base64: String = "encoded-image") -> RRScreenshotFrame {
            let frame = RRScreenshotFrame()
            frame.type = "screenshot"
            frame.base64 = base64
            return frame
        }

        /// The capture path's sequence: verdict, then the backoff note, then the remembered hash.
        /// Returns whether the frame would have been sent.
        private func render(
            _ frame: RRScreenshotFrame,
            lastHash: inout Int?,
            backoff: PostHogReplayCaptureBackoff
        ) -> Bool {
            let verdict = PostHogReplayIntegration.frameVerdict(
                wireframeDict: frame.toDict(),
                lastImageHash: lastHash,
                hasPendingSnapshotData: false
            )
            guard !verdict.unchanged else {
                backoff.noteFrame(unchanged: true)
                return false
            }
            lastHash = verdict.hash
            backoff.noteFrame(unchanged: false)
            return true
        }

        @Test("an unchanged screenshot engages the backoff after three unchanged frames")
        func unchangedFrameEngagesBackoff() {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(10)
            var lastHash: Int?

            #expect(render(frame(), lastHash: &lastHash, backoff: backoff))

            for _ in 0 ..< 2 {
                #expect(render(frame(), lastHash: &lastHash, backoff: backoff) == false)
            }
            #expect(backoff.isInBackoffForTesting == false)

            #expect(render(frame(), lastHash: &lastHash, backoff: backoff) == false)
            #expect(backoff.isInBackoffForTesting)
            #expect(backoff.shouldCapture() == false)
        }

        @Test("a changed screenshot restores the full rate")
        func changedFrameResetsBackoff() {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(10)
            var lastHash: Int?
            for _ in 0 ..< 4 {
                _ = render(frame(), lastHash: &lastHash, backoff: backoff)
            }
            #expect(backoff.isInBackoffForTesting)

            #expect(render(frame("changed-image"), lastHash: &lastHash, backoff: backoff))
            #expect(backoff.isInBackoffForTesting == false)
            #expect(backoff.shouldCapture())
        }

        @Test("the frame hash is the encoded image's hash, and nil without an image")
        func frameHashUsesBase64() {
            #expect(PostHogReplayIntegration.frameHash(for: frame().toDict()) == "encoded-image".hashValue)
            #expect(PostHogReplayIntegration.frameHash(for: RRScreenshotFrame().toDict()) == nil)
        }
    }

    @Suite("Replay capture interval")
    struct PostHogReplayCaptureIntervalTests {
        @Test("throttleDelay is clamped so trailing delivery cannot spin the run loop", arguments: [
            (0, PostHogReplayCaptureBackoff.minimumBaseInterval),
            (-1, PostHogReplayCaptureBackoff.minimumBaseInterval),
            (0.01, PostHogReplayCaptureBackoff.minimumBaseInterval),
            (.nan, 1),
            (.infinity, 1),
            (-.infinity, 1),
            (0.5, 0.5),
        ] as [(TimeInterval, TimeInterval)])
        func captureInterval(_ throttleDelay: TimeInterval, _ expected: TimeInterval) {
            #expect(PostHogReplayIntegration.captureInterval(throttleDelay: throttleDelay) == expected)
        }
    }

    @Suite("Backed-off structure change")
    struct PostHogReplayStructureChangeTests {
        private func engagedBackoff(base: TimeInterval = 1) -> PostHogReplayCaptureBackoff {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(base)
            for _ in 0 ..< 3 {
                backoff.noteFrame(unchanged: true)
            }
            return backoff
        }

        /// The first walk inside the idle interval only records the baseline.
        private func backedOff(structure: Int) -> PostHogReplayCaptureBackoff {
            let backoff = engagedBackoff()
            #expect(backoff.shouldCapture(structure: { structure }) == false)
            return backoff
        }

        @Test("a changed structure captures at once, and the changed frame leaves backoff")
        func changedStructureCaptures() {
            let backoff = backedOff(structure: 1)

            #expect(backoff.shouldCapture(structure: { 2 }))
            backoff.noteFrame(unchanged: false)
            #expect(backoff.isInBackoffForTesting == false)
        }

        @Test("a change whose capture was dropped stays admitted until a frame reports")
        func droppedCaptureStaysAdmitted() {
            let backoff = backedOff(structure: 1)

            #expect(backoff.shouldCapture(structure: { 2 }))
            #expect(backoff.shouldCapture(structure: { 2 }))
            backoff.noteFrame(unchanged: true)
            #expect(backoff.shouldCapture(structure: { 2 }) == false)
        }

        @Test("an unchanged structure keeps waiting for the idle interval")
        func sameStructureWaits() {
            let backoff = backedOff(structure: 1)

            #expect(backoff.shouldCapture(structure: { 1 }) == false)
            #expect(backoff.isInBackoffForTesting)
        }

        @Test("a structure change the render cannot see costs one frame and keeps backing off")
        func invisibleStructureChangeKeepsBackoff() {
            let backoff = backedOff(structure: 1)
            let interval = backoff.idleIntervalForTesting

            #expect(backoff.shouldCapture(structure: { 2 }))
            backoff.noteFrame(unchanged: true)
            #expect(backoff.isInBackoffForTesting)
            #expect(backoff.idleIntervalForTesting > interval)
            #expect(backoff.shouldCapture(structure: { 2 }) == false)
        }

        @Test("a toast appearing right after an idle render still captures")
        func changeAfterIdleRenderCaptures() {
            let backoff = engagedBackoff(base: PostHogReplayCaptureBackoff.minimumBaseInterval)
            #expect(backoff.shouldCapture(structure: { 1 }) == false)
            Thread.sleep(forTimeInterval: PostHogReplayCaptureBackoff.minimumBaseInterval * 2)

            #expect(backoff.shouldCapture(structure: { 1 }))
            #expect(backoff.shouldCapture(structure: { 2 }))
        }

        @Test("when not backed off the structure is never walked")
        func notBackedOffSkipsWalk() {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(10)
            var walks = 0
            let walk: () -> Int? = {
                walks += 1
                return 1
            }

            #expect(backoff.shouldCapture(structure: walk))
            backoff.noteFrame(unchanged: true)
            #expect(backoff.shouldCapture(structure: walk))
            #expect(walks == 0)
        }
    }

    @Suite("Structure fingerprint")
    @MainActor
    struct PostHogReplayStructureFingerprintTests {
        private func screen() -> (root: UIView, label: UILabel) {
            let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let label = UILabel(frame: CGRect(x: 16, y: 16, width: 200, height: 20))
            label.text = "Loading"
            root.addSubview(label)
            return (root, label)
        }

        private func fingerprint(
            _ view: UIView,
            nodeLimit: Int = PostHogReplayIntegration.structureFingerprintNodeLimit,
            depthLimit: Int = PostHogReplayIntegration.structureFingerprintDepthLimit
        ) -> Int {
            PostHogReplayIntegration.structureFingerprint(of: view, nodeLimit: nodeLimit, depthLimit: depthLimit)
        }

        private func withoutImplicitAnimations(_ body: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            body()
            CATransaction.commit()
        }

        @Test("a toast appearing and leaving changes the fingerprint each time")
        func toastChangesFingerprint() {
            let (root, _) = screen()
            let idle = fingerprint(root)

            let toast = UIView(frame: CGRect(x: 16, y: 560, width: 288, height: 48))
            root.addSubview(toast)
            let showing = fingerprint(root)
            #expect(showing != idle)

            toast.removeFromSuperview()
            #expect(fingerprint(root) == idle)
        }

        @Test("label text, visibility and geometry change the fingerprint")
        func visibleChangesChangeFingerprint() {
            let (root, label) = screen()
            let base = fingerprint(root)

            label.text = "Done"
            #expect(fingerprint(root) != base)
            label.text = "Loading"

            label.isHidden = true
            #expect(fingerprint(root) != base)
            label.isHidden = false

            label.frame.origin.y = 40
            #expect(fingerprint(root) != base)
        }

        @Test("a color-only change on a fixed label changes the fingerprint")
        func colorChangesChangeFingerprint() {
            let (root, label) = screen()
            label.textColor = .black
            let base = fingerprint(root)

            label.textColor = .red
            #expect(fingerprint(root) != base)
            label.textColor = .black
            #expect(fingerprint(root) == base)

            let background = label.backgroundColor
            label.backgroundColor = .yellow
            #expect(fingerprint(root) != base)
            label.backgroundColor = background
            #expect(fingerprint(root) == base)
        }

        @Test("churn inside a hidden subtree does not change the fingerprint")
        func hiddenSubtreeIgnored() {
            let (root, label) = screen()
            label.isHidden = true
            let base = fingerprint(root)

            label.text = "Done"
            label.addSubview(UIView())
            #expect(fingerprint(root) == base)
        }

        @Test("a change that only reaches a view's layer changes the fingerprint")
        func viewLayerChangesChangeFingerprint() {
            let (root, label) = screen()
            let base = fingerprint(root)

            let drawn = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
            withoutImplicitAnimations { label.layer.contents = drawn.cgImage }
            #expect(fingerprint(root) != base)

            withoutImplicitAnimations { label.layer.contents = nil }
            #expect(fingerprint(root) == base)
        }

        @Test("a layer with no view changes the fingerprint when it appears or changes")
        func viewlessLayerChangesChangeFingerprint() {
            let (root, _) = screen()
            let idle = fingerprint(root)

            let layer = CALayer()
            layer.frame = CGRect(x: 0, y: 0, width: 240, height: 48)
            withoutImplicitAnimations { root.layer.addSublayer(layer) }
            let added = fingerprint(root)
            #expect(added != idle)

            withoutImplicitAnimations { layer.backgroundColor = UIColor.magenta.cgColor }
            let colored = fingerprint(root)
            #expect(colored != added)

            withoutImplicitAnimations { layer.backgroundColor = UIColor.cyan.cgColor }
            #expect(fingerprint(root) != colored)
            withoutImplicitAnimations { layer.backgroundColor = UIColor(red: 1, green: 0, blue: 0.99, alpha: 1).cgColor }
            #expect(fingerprint(root) != colored)
            withoutImplicitAnimations { layer.backgroundColor = UIColor.magenta.cgColor }
            #expect(fingerprint(root) == colored)

            withoutImplicitAnimations { layer.position.y += 10 }
            #expect(fingerprint(root) != colored)

            withoutImplicitAnimations { layer.removeFromSuperlayer() }
            #expect(fingerprint(root) == idle)
        }

        @Test("a running animation does not change the fingerprint")
        func runningAnimationIgnored() {
            let (root, _) = screen()
            let layer = CALayer()
            layer.frame = CGRect(x: 0, y: 0, width: 240, height: 48)
            withoutImplicitAnimations { root.layer.addSublayer(layer) }
            let base = fingerprint(root)

            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = 0
            move.toValue = 200
            move.duration = 60
            layer.add(move, forKey: "move")

            #expect(fingerprint(root) == base)
        }

        @Test("churn inside a hidden layer does not change the fingerprint")
        func hiddenLayerIgnored() {
            let (root, _) = screen()
            let layer = CALayer()
            withoutImplicitAnimations {
                layer.isHidden = true
                root.layer.addSublayer(layer)
            }
            let base = fingerprint(root)

            withoutImplicitAnimations {
                layer.backgroundColor = UIColor.magenta.cgColor
                layer.addSublayer(CALayer())
            }
            #expect(fingerprint(root) == base)
        }

        @Test("the walk stops at the depth limit")
        func walkDepthIsBounded() {
            let (root, _) = screen()
            let parent = CALayer()
            let child = CALayer()
            withoutImplicitAnimations {
                parent.addSublayer(child)
                root.layer.addSublayer(parent)
            }
            let shallow = fingerprint(root, depthLimit: 2)
            let deep = fingerprint(root, depthLimit: 3)

            withoutImplicitAnimations { child.backgroundColor = UIColor.magenta.cgColor }
            #expect(fingerprint(root, depthLimit: 2) == shallow)
            #expect(fingerprint(root, depthLimit: 3) != deep)
        }

        @Test("the walk stops at the node limit")
        func walkIsBounded() {
            let (root, label) = screen()
            let rootOnly = fingerprint(root, nodeLimit: 1)
            let withLabel = fingerprint(root, nodeLimit: 2)

            label.text = "Done"
            #expect(fingerprint(root, nodeLimit: 1) == rootOnly)
            #expect(fingerprint(root, nodeLimit: 2) != withLabel)
        }
    }

    @Suite("Replay frames and session inactivity", .serialized, .resetsGlobalState)
    @MainActor
    struct PostHogReplayIdleSessionTests {
        @Test("a frame on an idle screen doesn't rotate an inactive session")
        func idleFrameKeepsSession() async throws {
            try await withMockedClock { clock in
                let lifecycle = MockApplicationLifecyclePublisher()
                let previousLifecycle = DI.main.appLifecyclePublisher
                DI.main.appLifecyclePublisher = lifecycle
                defer { DI.main.appLifecyclePublisher = previousLifecycle }

                let config = PostHogConfig(projectToken: "phc_replayIdleSession")
                config.disableReachabilityForTesting = true
                PostHogReplayIntegration.clearInstalls()
                let sdk = PostHogSDK.with(config)
                let integration = PostHogReplayIntegration()
                _ = integration.install(sdk)
                defer {
                    integration.uninstall(sdk)
                    sdk.close()
                }

                lifecycle.simulateAppDidBecomeActive()
                let original = try #require(sdk.sessionManager.getNextSessionId())
                sdk.sessionManager.touchSession()
                clock.date.addTimeInterval(60 * 31)

                let wireframe = RRScreenshotFrame()
                wireframe.type = "screenshot"
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
                integration.captureSnapshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: nil,
                    postHog: sdk,
                    timestampDate: clock.date
                )
                PostHogReplayIntegration.dispatchQueue.sync {}

                #expect(sdk.sessionManager.getSessionId(readOnly: true) == original)
            }
        }
    }

    @Suite("Unchanged frames across windows", .serialized)
    @MainActor
    struct PostHogReplayWindowSwitchDedupTests {
        @Test("returning to an unchanged window after another window sends its frame again")
        func returningWindowResendsFrame() {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }

            let lock = NSLock()
            var snapshots = 0
            let config = PostHogConfig(projectToken: "phc_replayWindowSwitch", host: "http://localhost:9001")
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.setBeforeSend { event in
                if event.event == "$snapshot" {
                    lock.withLock { snapshots += 1 }
                }
                return nil
            }
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }
            let integration = PostHogReplayIntegration()
            let screen = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let overlay = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))

            func sendFrame(_ window: UIWindow, text: String) {
                let wireframe = RRScreenshotFrame()
                wireframe.type = "screenshot"
                wireframe.base64 = text
                integration.captureSnapshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: nil,
                    postHog: sdk,
                    timestampDate: Date()
                )
                PostHogReplayIntegration.dispatchQueue.sync {}
            }

            sendFrame(screen, text: "Screen")
            sendFrame(screen, text: "Screen")
            #expect(lock.withLock { snapshots } == 1)
            sendFrame(overlay, text: "Overlay")
            sendFrame(screen, text: "Screen")
            #expect(lock.withLock { snapshots } == 3)
        }
    }
#endif
