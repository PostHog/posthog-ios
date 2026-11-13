#if os(iOS)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    @Suite("Replay never copies an app-defined layer's presentation", .serialized)
    @MainActor
    struct PostHogAppLayerPresentationTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        private func makeSut() -> Sut {
            let config = PostHogConfig(projectToken: "phc_appLayerPresentationTest")
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

        private func commit() async throws {
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        /// A masked field under an app-defined container, committed and settled.
        private func fieldUnderAppLayer(in window: UIWindow) async throws -> (container: UIView, field: UIView) {
            let container = AppLayerView(frame: CGRect(x: 20, y: 20, width: 160, height: 160))
            let field = UITextField(frame: CGRect(x: 10, y: 10, width: 120, height: 60))
            field.text = "secret"
            container.addSubview(field)
            window.addSubview(container)
            window.layoutIfNeeded()
            try await commit()
            try #require(container.layer.isAppDefined)
            AppLayer.copies = 0
            return (container, field)
        }

        @Test("Only layer classes the app defines count as app-defined")
        func appDefinedClassification() {
            #expect(!CALayer().isAppDefined)
            #expect(!CAShapeLayer().isAppDefined)
            #expect(!CAGradientLayer().isAppDefined)
            #expect(!UIView().layer.isAppDefined)
            #expect(!UITextField().layer.isAppDefined)
            #expect(AppLayer().isAppDefined)
        }

        @Test("A masked field under a still app-defined layer is masked where it sits")
        func fieldUnderStillAppLayerIsMaskedWhereItSits() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let (_, field) = try await fieldUnderAppLayer(in: window)

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(AppLayer.copies == 0)
            #expect(rects == [field.convert(field.bounds, to: window)])
        }

        @Test("A masked field under a moving app-defined layer is masked over the whole window")
        func fieldUnderMovingAppLayerFailsClosed() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let (container, _) = try await fieldUnderAppLayer(in: window)
            try await hold(container.layer, keyPath: "position", at: NSValue(cgPoint: CGPoint(x: 100, y: 250)))
            AppLayer.copies = 0

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(AppLayer.copies == 0)
            #expect(rects.contains { $0.contains(window.bounds) }, "\(rects)")
        }

        @Test("A masked view moved under an app-defined layer in this turn is masked where it draws")
        func viewMovedUnderAppLayerBeforeCommitIsMaskedWhereItDraws() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let (container, field) = try await fieldUnderAppLayer(in: window)

            // No animation and no commit: until Core Animation commits, the model is ahead of what's drawn.
            field.frame.origin.y = 150

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            // The field's own layer is a system one, so its presentation is safe to read; the container doesn't move.
            let drawn = try #require(field.layer.presentation()).frame.offsetBy(dx: container.frame.minX, dy: container.frame.minY)
            #expect(AppLayer.copies == 0)
            #expect(rects.contains { $0.contains(drawn) }, "drawn at \(drawn), masked \(rects)")
        }

        @Test("A transparent app-defined masked view that's animating stays masked")
        func animatingTransparentAppLayerStaysMasked() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let view = AppLayerView(frame: CGRect(x: 20, y: 40, width: 120, height: 60))
            view.accessibilityIdentifier = "ph-no-capture"
            view.alpha = 0
            window.addSubview(view)
            window.layoutIfNeeded()
            try await commit()
            try await hold(view.layer, keyPath: "opacity", at: 1)
            AppLayer.copies = 0

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(AppLayer.copies == 0)
            #expect(rects.contains { $0.contains(view.frame) }, "\(rects)")
        }

        @Test("A collapsed clipping app-defined view that's animating keeps its children masked")
        func collapsingAppLayerKeepsChildrenMasked() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let container = AppLayerView(frame: .zero)
            container.clipsToBounds = true
            let field = UITextField(frame: CGRect(x: 10, y: 10, width: 120, height: 60))
            field.text = "secret"
            container.addSubview(field)
            window.addSubview(container)
            window.layoutIfNeeded()
            try await commit()
            try await hold(container.layer, keyPath: "bounds", at: NSValue(cgRect: CGRect(x: 0, y: 0, width: 160, height: 160)))
            AppLayer.copies = 0

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(AppLayer.copies == 0)
            #expect(rects.contains { $0.contains(window.bounds) }, "\(rects)")
        }

        @Test("An unclipped masked image view with an app-defined layer is masked wherever a replaced image could draw")
        func unclippedAppLayerImageViewFailsClosed() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let imageView = AppLayerImageView(image: try magentaImage(CGSize(width: 20, height: 20)))
            imageView.frame = CGRect(x: 80, y: 120, width: 40, height: 40)
            imageView.contentMode = .center
            imageView.accessibilityIdentifier = "ph-no-capture"
            window.addSubview(imageView)
            window.layoutIfNeeded()
            try await commit()
            AppLayer.copies = 0

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(AppLayer.copies == 0)
            #expect(rects.contains { $0.contains(window.bounds) }, "\(rects)")
        }

        @Test("A window of UIKit views holds no app-defined layer and keeps its motion frames")
        func uikitWindowKeepsMotionFrames() async throws {
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let field = UITextField()
            field.text = "secret"
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            let stack = UIStackView(arrangedSubviews: [
                field, UILabel(), UIImageView(image: UIImage(systemName: "star")), UISwitch(), UISlider(), spinner,
                UIButton(type: .system), UIVisualEffectView(effect: UIBlurEffect(style: .regular)), UITableView(),
            ])
            stack.axis = .vertical
            stack.frame = window.bounds
            window.addSubview(stack)
            window.layoutIfNeeded()
            try await commit()

            #expect(!window.layer.containsAppDefinedLayer)
            #expect(window.toImage(preferFidelityRenderer: false) != nil)
        }

        @Test("A motion frame of a window holding an app-defined layer is skipped")
        func motionFrameWithAppLayerIsSkipped() async throws {
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            _ = try await fieldUnderAppLayer(in: window)

            #expect(window.toImage(preferFidelityRenderer: false) == nil)
            #expect(AppLayer.copies == 0)
        }
    }

    /// An app-defined layer that counts the copies `presentation()` makes of it. A Swift layer without its own
    /// `init(layer:)` traps on the first one.
    private final class AppLayer: CALayer {
        nonisolated(unsafe) static var copies = 0

        override init() {
            super.init()
        }

        override init(layer: Any) {
            Self.copies += 1
            super.init(layer: layer)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private final class AppLayerView: UIView {
        override class var layerClass: AnyClass {
            AppLayer.self
        }
    }

    private final class AppLayerImageView: UIImageView {
        override class var layerClass: AnyClass {
            AppLayer.self
        }
    }
#endif
