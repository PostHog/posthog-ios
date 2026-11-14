//
//  Masking coverage for Compose Multiplatform screens. Compose Multiplatform draws its whole UI
//  into a few UIKit views (a container, a Metal surface and input views) with no UIKit text field,
//  label or image view per element, so the heuristic walk can't find what to mask inside them.
//  Kotlin/Native registers those Kotlin classes with the Objective-C runtime under names such as
//  `SampleAppandroidx.compose.ui.window.ComposeContainerView3`: the app module's name, the Kotlin
//  class's fully qualified name and a counter. This suite registers UIView subclasses under names
//  of that shape, so it needs no Compose dependency.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// A UIView subclass registered under `name`, as Kotlin/Native registers a Kotlin subclass of UIView.
    private func composeViewClass(_ name: String) -> UIView.Type {
        if let existing = NSClassFromString(name) as? UIView.Type {
            return existing
        }
        let cls: AnyClass = objc_allocateClassPair(UIView.self, name, 0)!
        objc_registerClassPair(cls)
        return cls as! UIView.Type
    }

    private let composeContainerView = composeViewClass("SampleAppandroidx.compose.ui.window.ComposeContainerView3")
    private let composeSurfaceView = composeViewClass("SampleAppandroidx.compose.ui.window.SurfaceMetalView7")

    @Suite("Replay masking for Compose Multiplatform views", .serialized)
    @MainActor
    struct PostHogComposeMultiplatformMaskingTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        private func makeSut(maskText: Bool, maskImages: Bool) -> Sut {
            let config = PostHogConfig(projectToken: "phc_composeMultiplatformMaskingTest")
            config.disableReachabilityForTesting = true
            config.sessionReplayConfig.maskAllTextInputs = maskText
            config.sessionReplayConfig.maskAllImages = maskImages
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

        /// A Compose screen as Compose Multiplatform 1.12 lays it out: a container holding the
        /// Metal surface it draws into.
        private func makeComposeScreen(frame: CGRect) -> UIView {
            let container = composeContainerView.init(frame: frame)
            container.addSubview(composeSurfaceView.init(frame: CGRect(origin: .zero, size: frame.size)))
            return container
        }

        @Test("A Compose Multiplatform view is masked whole under maskAllTextInputs")
        func maskedUnderMaskAllTextInputs() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let window = makeWindow(containing: makeComposeScreen(frame: CGRect(x: 0, y: 60, width: 320, height: 500)))

            // the container and the surface filling it
            let rects = sut.integration.collectMaskableRects(in: window) ?? []
            #expect(!rects.isEmpty && rects.allSatisfy { $0 == CGRect(x: 0, y: 60, width: 320, height: 500) })
        }

        @Test("A Compose Multiplatform view is masked whole under maskAllImages")
        func maskedUnderMaskAllImages() {
            let sut = makeSut(maskText: false, maskImages: true)
            defer { teardown(sut) }

            let window = makeWindow(containing: makeComposeScreen(frame: CGRect(x: 0, y: 60, width: 320, height: 500)))

            // the container and the surface filling it
            let rects = sut.integration.collectMaskableRects(in: window) ?? []
            #expect(!rects.isEmpty && rects.allSatisfy { $0 == CGRect(x: 0, y: 60, width: 320, height: 500) })
        }

        @Test("A Compose Multiplatform view isn't masked when text and image masking are off")
        func unmaskedWithMaskingOff() {
            let sut = makeSut(maskText: false, maskImages: false)
            defer { teardown(sut) }

            let window = makeWindow(containing: makeComposeScreen(frame: CGRect(x: 0, y: 60, width: 320, height: 500)))

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("A ph-no-mask token on a Compose Multiplatform view unmasks it")
        func noMaskTokenUnmasks() {
            let sut = makeSut(maskText: true, maskImages: true)
            defer { teardown(sut) }

            let screen = makeComposeScreen(frame: CGRect(x: 0, y: 60, width: 320, height: 500))
            screen.accessibilityIdentifier = "ph-no-mask"
            let window = makeWindow(containing: screen)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("A sensitive UIKit view drawing outside a Compose Multiplatform view stays masked")
        func unclippedSensitiveSubviewMasked() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let screen = makeComposeScreen(frame: CGRect(x: 0, y: 60, width: 320, height: 500))
            // an interop text field drawing below the screen's rect
            let field = UITextField(frame: CGRect(x: 0, y: 500, width: 320, height: 40))
            field.text = "secret"
            screen.addSubview(field)
            let window = makeWindow(containing: screen)

            let rects = sut.integration.collectMaskableRects(in: window) ?? []
            #expect(rects.contains(CGRect(x: 0, y: 60, width: 320, height: 500)))
            #expect(rects.contains(CGRect(x: 0, y: 560, width: 320, height: 40)))
        }

        @Test("A ph-no-capture Compose Multiplatform view masks its descendants too")
        func noCaptureMasksDescendants() {
            let sut = makeSut(maskText: false, maskImages: false)
            defer { teardown(sut) }

            let screen = makeComposeScreen(frame: CGRect(x: 0, y: 60, width: 320, height: 500))
            screen.accessibilityIdentifier = "ph-no-capture"
            // an unclipped subview drawing below the screen's rect
            screen.addSubview(UIView(frame: CGRect(x: 0, y: 500, width: 320, height: 40)))
            let window = makeWindow(containing: screen)

            let rects = sut.integration.collectMaskableRects(in: window) ?? []
            #expect(rects.contains(CGRect(x: 0, y: 60, width: 320, height: 500)))
            #expect(rects.contains(CGRect(x: 0, y: 560, width: 320, height: 40)))
        }

        @Test("A Compose Multiplatform surface is masked without its container")
        func surfaceMaskedAlone() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let window = makeWindow(containing: composeSurfaceView.init(frame: CGRect(x: 10, y: 20, width: 300, height: 400)))

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 10, y: 20, width: 300, height: 400)])
        }

        @Test("A view whose class name only mentions Compose elsewhere isn't masked")
        func unrelatedClassNameUnmasked() {
            let sut = makeSut(maskText: true, maskImages: true)
            defer { teardown(sut) }

            let other = composeViewClass("SampleAppcom.example.compose.ui.windowless.PlainView1")
            let window = makeWindow(containing: other.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100)))

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }
    }
#endif
