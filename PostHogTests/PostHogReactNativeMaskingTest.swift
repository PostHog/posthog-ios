//
//  Masking coverage for React Native component views. React Native's New
//  Architecture (Fabric) renders text as RCTParagraphComponentView and images as
//  RCTImageComponentView — not the legacy RCTTextView/RCTImageView — and
//  react-native-svg draws into RNSVGSvgView. The integration resolves all of
//  these classes by name (NSClassFromString) when it is created, so this suite
//  registers plain UIView stubs under the real Objective-C runtime names and
//  needs no React Native dependency: the stubs resolve exactly like the real
//  classes do in a React Native host app.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    // Registered with the Objective-C runtime under the exact names React Native
    // exports, so NSClassFromString finds them at integration init.
    @objc(RCTParagraphComponentView) private final class FabricParagraphViewStub: UIView {}
    @objc(RCTImageComponentView) private final class FabricImageViewStub: UIView {}
    @objc(RNSVGSvgView) private final class SvgViewStub: UIView {}
    @objc(RNSVGRenderable) private class SvgRenderableViewStub: UIView {}
    @objc(RNSVGGroup) private class SvgGroupViewStub: SvgRenderableViewStub {}
    @objc(RNSVGText) private final class SvgTextViewStub: SvgGroupViewStub {}
    @objc(RNSVGImage) private final class SvgImageViewStub: SvgRenderableViewStub {}

    @Suite("Replay masking for React Native (Fabric) component views", .serialized)
    @MainActor
    struct PostHogReactNativeMaskingTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        /// An integration with a bound config, so the maskAllTextInputs/maskAllImages
        /// heuristics are live (a bare `PostHogReplayIntegration()` has no config and
        /// skips them). Resets the static install flag a prior replay suite may have
        /// left set, so this install binds fresh instead of no-opping onto a stale one.
        private func makeSut(maskText: Bool, maskImages: Bool) -> Sut {
            let config = PostHogConfig(projectToken: "phc_reactNativeMaskingTest")
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

        private func makeWindow(containing views: UIView...) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            for view in views {
                window.addSubview(view)
            }
            window.layoutIfNeeded()
            return window
        }

        @Test("Fabric paragraph view is masked under maskAllTextInputs")
        func fabricParagraphViewMasked() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let paragraph = FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            let window = makeWindow(containing: paragraph)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 24, y: 120, width: 200, height: 32)])
        }

        @Test("Fabric image component view is masked under maskAllImages")
        func fabricImageComponentViewMasked() {
            let sut = makeSut(maskText: false, maskImages: true)
            defer { teardown(sut) }

            let image = FabricImageViewStub(frame: CGRect(x: 40, y: 200, width: 160, height: 100))
            let window = makeWindow(containing: image)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 40, y: 200, width: 160, height: 100)])
        }

        @Test("react-native-svg image content is masked under maskAllImages")
        func svgImageMasked() {
            let sut = makeSut(maskText: false, maskImages: true)
            defer { teardown(sut) }

            let svg = SvgViewStub(frame: CGRect(x: 10, y: 300, width: 300, height: 180))
            svg.addSubview(SvgImageViewStub())
            let window = makeWindow(containing: svg)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 10, y: 300, width: 300, height: 180)])
        }

        @Test("react-native-svg text content is masked under maskAllTextInputs")
        func svgTextMasked() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let svg = SvgViewStub(frame: CGRect(x: 10, y: 300, width: 300, height: 180))
            let group = SvgGroupViewStub()
            group.addSubview(SvgTextViewStub())
            svg.addSubview(group)
            let window = makeWindow(containing: svg)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 10, y: 300, width: 300, height: 180)])
        }

        @Test("A ph-no-mask accessibilityIdentifier token unmasks a Fabric paragraph view")
        func noMaskIdentifierTokenUnmasksParagraph() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let paragraph = FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            // Compound identifier pins the substring match (React Native example:
            // testID="screen-title-ph-no-mask").
            paragraph.accessibilityIdentifier = "screen-title ph-no-mask"
            let window = makeWindow(containing: paragraph)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("A sensitive UITextField nested under a ph-no-mask ancestor is not collected")
        func noMaskAncestorSkipsSensitiveSubtree() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let container = UIView(frame: CGRect(x: 0, y: 80, width: 320, height: 200))
            container.accessibilityIdentifier = "safe-chrome ph-no-mask"
            container.addSubview(UITextField(frame: CGRect(x: 12, y: 12, width: 160, height: 40)))
            container.addSubview(FabricParagraphViewStub(frame: CGRect(x: 12, y: 64, width: 160, height: 32)))
            let window = makeWindow(containing: container)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("A ph-no-mask accessibilityLabel token unmasks Fabric paragraph view")
        func noMaskLabelTokenUnmasksParagraph() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let paragraph = FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            paragraph.accessibilityLabel = "ph-no-mask"
            let window = makeWindow(containing: paragraph)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("A ph-no-mask token is matched case-insensitively")
        func noMaskTokenIsCaseInsensitive() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let paragraph = FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            paragraph.accessibilityIdentifier = "Screen-Title PH-NO-MASK"
            let window = makeWindow(containing: paragraph)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("A ph-no-mask ancestor takes precedence over a ph-no-capture descendant")
        func noMaskAncestorOutranksNoCaptureDescendant() {
            let sut = makeSut(maskText: false, maskImages: false)
            defer { teardown(sut) }

            let container = UIView(frame: CGRect(x: 0, y: 80, width: 320, height: 200))
            container.accessibilityIdentifier = "safe-chrome ph-no-mask"
            let tagged = FabricParagraphViewStub(frame: CGRect(x: 12, y: 12, width: 160, height: 32))
            tagged.accessibilityIdentifier = "ph-no-capture"
            container.addSubview(tagged)
            let window = makeWindow(containing: container)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("nothing is masked with both flags off")
        func nothingMaskedWithFlagsOff() {
            let sut = makeSut(maskText: false, maskImages: false)
            defer { teardown(sut) }

            let svg = SvgViewStub(frame: CGRect(x: 10, y: 340, width: 300, height: 180))
            svg.addSubview(SvgTextViewStub())
            svg.addSubview(SvgImageViewStub())
            let window = makeWindow(
                containing: FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32)),
                FabricImageViewStub(frame: CGRect(x: 40, y: 200, width: 160, height: 100)),
                svg
            )

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("text-only React Native views are not masked under maskAllImages")
        func textViewsNotMaskedByImageSetting() {
            let sut = makeSut(maskText: false, maskImages: true)
            defer { teardown(sut) }

            let svg = SvgViewStub(frame: CGRect(x: 10, y: 340, width: 300, height: 180))
            let group = SvgGroupViewStub()
            group.addSubview(SvgTextViewStub())
            svg.addSubview(group)
            let window = makeWindow(
                containing: FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32)),
                svg
            )

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("image-only React Native views are not masked under maskAllTextInputs")
        func imageViewsNotMaskedByTextSetting() {
            let sut = makeSut(maskText: true, maskImages: false)
            defer { teardown(sut) }

            let svg = SvgViewStub(frame: CGRect(x: 10, y: 340, width: 300, height: 180))
            svg.addSubview(SvgImageViewStub())
            let window = makeWindow(
                containing: FabricImageViewStub(frame: CGRect(x: 40, y: 200, width: 160, height: 100)),
                svg
            )

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }
    }
    /// Pins that reading the label carrier via `super.accessibilityLabel` sees only an
    /// explicitly assigned label, never one UIKit or React Native derives from content.
    /// Load-bearing for `ph-no-mask`: a derived label would let user or server copy
    /// containing the token unmask a subtree.
    @Suite("Accessibility token carriers", .serialized)
    @MainActor
    struct PostHogAccessibilityTokenCarrierTest {
        /// Overrides the getter the way RCTView and UILabel do.
        private final class OverridingLabelView: UIView {
            override var accessibilityLabel: String? {
                get { "ph-no-mask" }
                set { _ = newValue }
            }
        }

        @Test("An explicitly assigned accessibilityLabel carries the token")
        func explicitLabelIsRead() {
            let view = UIView()
            view.accessibilityLabel = "ph-no-mask"

            #expect(view.isNoMask())
        }

        @Test("A UILabel's text-derived accessibilityLabel does not carry the token")
        func textDerivedLabelIsNotRead() {
            let label = UILabel()
            label.text = "ph-no-mask"

            // UIKit does not populate `accessibilityLabel` from `text` at the property level
            // outside an active accessibility context, so the token never reaches the match.
            #expect(label.accessibilityLabel == nil)
            #expect(label.isNoMask() == false)
        }

        @Test("A subclass override of accessibilityLabel does not carry the token")
        func overriddenLabelIsNotRead() {
            let view = OverridingLabelView()

            #expect(view.accessibilityLabel == "ph-no-mask")
            #expect(view.isNoMask() == false)
        }

        @Test("The same carriers apply to ph-no-capture")
        func noCaptureUsesSameCarriers() {
            let label = UILabel()
            label.text = "ph-no-capture"

            #expect(label.isNoCapture() == false)
        }
    }

#endif
