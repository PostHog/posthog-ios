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

    @Suite("Replay masking for React Native (Fabric) component views", .serialized)
    @MainActor
    struct PostHogReactNativeMaskingTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        /// An integration with a bound config, so the maskAllTextInputs/maskAllImages
        /// heuristics are live (a bare `PostHogReplayIntegration()` has no config and
        /// skips them). Resets the static install flag a prior replay suite may have
        /// left set, so this install binds fresh instead of no-opping onto a stale one.
        private func makeSut(maskText: Bool, maskImages: Bool) -> Sut {
            let config = PostHogConfig(apiKey: "phc_reactNativeMaskingTest")
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

        @Test("react-native-svg root view is masked under maskAllImages")
        func svgViewMasked() {
            let sut = makeSut(maskText: false, maskImages: true)
            defer { teardown(sut) }

            let svg = SvgViewStub(frame: CGRect(x: 10, y: 300, width: 300, height: 180))
            let window = makeWindow(containing: svg)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 10, y: 300, width: 300, height: 180)])
        }

        @Test("nothing is masked with both flags off")
        func nothingMaskedWithFlagsOff() {
            let sut = makeSut(maskText: false, maskImages: false)
            defer { teardown(sut) }

            let window = makeWindow(
                containing: FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32)),
                FabricImageViewStub(frame: CGRect(x: 40, y: 200, width: 160, height: 100)),
                SvgViewStub(frame: CGRect(x: 10, y: 340, width: 300, height: 180))
            )

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("each class is gated by its matching flag, not the other one")
        func maskingGatedByMatchingFlag() {
            // maskAllImages alone must not mask text views...
            let imagesOnly = makeSut(maskText: false, maskImages: true)
            let paragraphWindow = makeWindow(
                containing: FabricParagraphViewStub(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            )
            #expect(imagesOnly.integration.collectMaskableRects(in: paragraphWindow) == [])
            teardown(imagesOnly)

            // ...and maskAllTextInputs alone must not mask image or SVG views.
            let textOnly = makeSut(maskText: true, maskImages: false)
            let imageWindow = makeWindow(
                containing: FabricImageViewStub(frame: CGRect(x: 40, y: 200, width: 160, height: 100)),
                SvgViewStub(frame: CGRect(x: 10, y: 340, width: 300, height: 180))
            )
            #expect(textOnly.integration.collectMaskableRects(in: imageWindow) == [])
            teardown(textOnly)
        }
    }
#endif
