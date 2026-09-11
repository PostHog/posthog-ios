//
//  Fail-closed masking coverage (GitHub issue #821). Three paths could put content
//  the config masks into an uploaded snapshot: a screenshot sent raw after the
//  masked render failed, and two visibility checks that skipped a subtree the
//  screenshot still draws — a zero-size non-clipping parent (React Native's default
//  `overflow: visible` wrapper) and a view whose model alpha already parked at 0
//  while it fades out.
//

#if os(iOS)
    import CoreGraphics
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing
    import UIKit

    /// A layer that reports an in-flight fade: the model opacity is 0 while the
    /// presentation layer the screenshot renders is still opaque. Deterministic stand-in
    /// for `UIView.animate { view.alpha = 0 }`, whose presentation values need a real
    /// render server commit.
    private final class FadingOutLayer: CALayer {
        override func presentation() -> Self? {
            let presentation = FadingOutLayer()
            presentation.bounds = bounds
            presentation.position = position
            presentation.opacity = 1
            // `presentationLayer` is imported as `-> Self?`, and this class is final,
            // so the cast always succeeds.
            return presentation as? Self
        }
    }

    private final class FadingOutView: UIView {
        override class var layerClass: AnyClass { FadingOutLayer.self }
    }

    @Suite("Replay masking fails closed", .serialized)
    @MainActor
    struct PostHogMaskFailClosedTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        private func makeSut() -> Sut {
            let config = PostHogConfig(projectToken: "phc_maskFailClosedTest")
            config.disableReachabilityForTesting = true
            config.sessionReplayConfig.maskAllTextInputs = true
            PostHogReplayIntegration.clearInstalls()
            let sdk = PostHogSDK.with(config)
            let integration = PostHogReplayIntegration()
            _ = integration.install(sdk)
            return (sdk, integration)
        }

        private func teardown(_ sut: Sut) {
            sut.integration.uninstall(sut.sdk)
            sut.sdk.close()
        }

        private func makeWindow(containing view: UIView) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            window.addSubview(view)
            window.layoutIfNeeded()
            return window
        }

        private func makeSecretLabel(frame: CGRect) -> UILabel {
            let label = UILabel(frame: frame)
            label.text = "SSN 123-45-6789"
            return label
        }

        // MARK: - Mask render failure

        /// An image whose pixel size rounds to zero, so `PostHogGraphicsImageRenderer`
        /// returns nil exactly as it does when the full-frame malloc or the CGContext fails.
        private func makeUnrenderableImage() -> UIImage {
            let pixel = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return UIImage(cgImage: pixel.makeImage()!, scale: 8, orientation: .up)
        }

        private func makeRenderableImage() -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
        }

        @Test("a screenshot whose masked render fails carries no image and is marked for dropping")
        func maskRenderFailureDropsTheFrame() {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = makeUnrenderableImage()
            wireframe.maskableWidgets = [CGRect(x: 0, y: 0, width: 10, height: 10)]

            let dict = wireframe.toDict()

            #expect(dict["base64"] == nil)
            #expect(wireframe.maskRenderFailed)
        }

        @Test("a screenshot with nothing to mask still sends the image")
        func unmaskedScreenshotStillSends() {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = makeRenderableImage()

            let dict = wireframe.toDict()

            #expect(dict["base64"] != nil)
            #expect(!wireframe.maskRenderFailed)
        }

        @Test("a successful masked render sends the redacted image")
        func maskedScreenshotSends() {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = makeRenderableImage()
            wireframe.maskableWidgets = [CGRect(x: 0, y: 0, width: 10, height: 10)]

            let dict = wireframe.toDict()

            #expect(dict["base64"] != nil)
            #expect(!wireframe.maskRenderFailed)
        }

        @Test("bridge completion reports the mask result without changing the legacy return value", arguments: [true, false])
        func bridgeCompletionReportsMaskResult(fails: Bool) async {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeWindow(containing: UIView())
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.maskableWidgets = [CGRect(x: 0, y: 0, width: 10, height: 10)]

            let captured = await withCheckedContinuation { continuation in
                let enqueued = sut.integration.renderAndEnqueueScreenshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: "Bridge opening",
                    postHog: sut.sdk,
                    timestampDate: Date(),
                    image: fails ? makeUnrenderableImage() : makeRenderableImage(),
                    episodeFirstFrame: true,
                    completion: { captured in
                        #expect(!Thread.isMainThread)
                        continuation.resume(returning: captured)
                    }
                )
                #expect(enqueued)
            }

            #expect(wireframe.maskRenderFailed == fails)
            #expect(captured == !fails)
        }

        @Test("completion reports unchanged and unencoded screenshots as not captured")
        func completionReportsSkippedScreenshots() async {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeWindow(containing: UIView())
            var results: [Bool] = []
            for base64 in ["encoded-screenshot", "encoded-screenshot", nil] as [String?] {
                let wireframe = RRWireframe()
                wireframe.type = "screenshot"
                wireframe.base64 = base64
                let captured = await withCheckedContinuation { continuation in
                    sut.integration.captureSnapshot(
                        wireframe,
                        window: window,
                        windowSize: window.bounds.size,
                        screenName: nil,
                        postHog: sut.sdk,
                        timestampDate: Date(),
                        completion: { continuation.resume(returning: $0) }
                    )
                }
                results.append(captured)
            }
            #expect(results == [true, false, false])
        }

        @Test("completion SPI reports unavailable capture asynchronously on main", arguments: [true, false], [true, false])
        func completionSPIReportsUnavailableCapture(configured: Bool, replayEnabled: Bool) async {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }
            let config = PostHogConfig(projectToken: "phc_bridgeCompletionTest", host: "http://localhost:9001")
            config.disableReachabilityForTesting = true
            config.sessionReplay = replayEnabled
            PostHogReplayIntegration.clearInstalls()
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }
            if !configured {
                sdk.close()
            }

            #expect(!sdk.captureSessionReplaySnapshot(episodeFirstFrame: true))
            var returned = false
            let captured = await withCheckedContinuation { continuation in
                sdk.captureSessionReplaySnapshot(episodeFirstFrame: true) { captured in
                    #expect(Thread.isMainThread)
                    #expect(returned)
                    continuation.resume(returning: captured)
                }
                returned = true
            }
            #expect(!captured)
        }

        private func captureSnapshotTypes(
            failures: [Bool],
            queueTogether: Bool = false,
            episodeFirstFrames: Set<Int> = []
        ) -> [[Int]] {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }

            let lock = NSLock()
            var captured: [[Int]] = []
            let config = PostHogConfig(projectToken: "phc_snapshotMetadataTest", host: "http://localhost:9001")
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.setBeforeSend { event in
                if event.event == "$snapshot", let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] {
                    lock.withLock { captured.append(snapshots.compactMap { $0["type"] as? Int }) }
                }
                return nil
            }
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }
            let integration = PostHogReplayIntegration()
            let window = makeWindow(containing: UIView())
            let queue = PostHogReplayIntegration.dispatchQueue

            if queueTogether {
                queue.suspend()
            }
            for (index, fails) in failures.enumerated() {
                let wireframe = RRWireframe()
                wireframe.type = "screenshot"
                wireframe.image = fails ? makeUnrenderableImage() : makeRenderableImage()
                wireframe.maskableWidgets = [CGRect(x: index * 5, y: 0, width: 10, height: 10)]
                integration.captureSnapshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: "Screen \(index)",
                    postHog: sdk,
                    timestampDate: Date(),
                    episodeFirstFrame: episodeFirstFrames.contains(index)
                )
                if !queueTogether {
                    queue.sync {}
                }
            }
            if queueTogether {
                queue.resume()
                queue.sync {}
            }
            return lock.withLock { captured }
        }

        @Test("first-frame failure preserves metadata for recovery")
        func firstFrameFailurePreservesMetadata() {
            #expect(captureSnapshotTypes(failures: [true, false]) == [[4, 2]])
        }

        @Test("a queued recovery frame includes metadata after the first render fails")
        func queuedRecoveryIncludesMetadata() {
            #expect(captureSnapshotTypes(failures: [true, false, false], queueTogether: true) == [[4, 2], [2]])
        }

        @Test("a later render failure does not resend metadata that was already sent")
        func laterFailureDoesNotResendMetadata() {
            #expect(captureSnapshotTypes(failures: [false, true, false]) == [[4, 2], [2]])
        }

        @Test("queued successful frames send metadata only once")
        func queuedSuccessesSendMetadataOnce() {
            #expect(captureSnapshotTypes(failures: [false, false], queueTogether: true) == [[4, 2], [2]])
        }

        @Test("a failed opening frame of a new bridge episode keeps its metadata pending")
        func failedEpisodeOpeningPreservesMetadata() {
            #expect(captureSnapshotTypes(failures: [false, true, false], episodeFirstFrames: [1]) == [[4, 2], [4, 2]])
        }

        // MARK: - Zero-size parents

        @Test("text inside a zero-size non-clipping parent is masked")
        func zeroSizeNonClippingParentIsTraversed() {
            let sut = makeSut()
            defer { teardown(sut) }

            let wrapper = UIView(frame: .zero)
            wrapper.clipsToBounds = false
            let label = makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            wrapper.addSubview(label)
            let window = makeWindow(containing: wrapper)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 24, y: 120, width: 200, height: 32)])
        }

        @Test("a zero-size clipping parent draws nothing, so its subtree is skipped")
        func zeroSizeClippingParentIsSkipped() {
            let sut = makeSut()
            defer { teardown(sut) }

            let wrapper = UIView(frame: .zero)
            wrapper.clipsToBounds = true
            wrapper.addSubview(makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32)))
            let window = makeWindow(containing: wrapper)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        // MARK: - Fading views

        @Test("text inside a view that is fading out is masked")
        func fadingOutParentIsTraversed() {
            let sut = makeSut()
            defer { teardown(sut) }

            let fading = FadingOutView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            fading.alpha = 0
            fading.addSubview(makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32)))
            let window = makeWindow(containing: fading)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 24, y: 120, width: 200, height: 32)])
        }

        @Test("a fully transparent view draws nothing, so its subtree is skipped")
        func transparentParentIsSkipped() {
            let sut = makeSut()
            defer { teardown(sut) }

            let transparent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            transparent.alpha = 0
            transparent.addSubview(makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32)))
            let window = makeWindow(containing: transparent)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }
    }
#endif
