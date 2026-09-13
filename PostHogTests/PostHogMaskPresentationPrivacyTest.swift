#if os(iOS) && TEST_PRESENTATION_MASKS
    import Combine
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    @Suite("Replay presentation privacy", .serialized)
    @MainActor
    struct PostHogMaskPresentationPrivacyTest {
        private final class Secrets {
            let controller: UIViewController
            let manual: UIHostingController<AnyView>
            let label = UILabel(frame: CGRect(x: 20, y: 100, width: 170, height: 32))
            let field = UITextField(frame: CGRect(x: 20, y: 150, width: 170, height: 32))
            let image = UIImageView(frame: CGRect(x: 20, y: 200, width: 100, height: 50))

            init(background: UIColor = .white) {
                controller = UIViewController()
                controller.view.backgroundColor = background
                manual = UIHostingController(rootView: AnyView(
                    Text("MANUAL SECRET").frame(maxWidth: .infinity, maxHeight: .infinity).postHogMask()
                ))
                if #available(iOS 16.4, *) { manual.safeAreaRegions = [] }
                controller.addChild(manual)
                manual.view.frame = CGRect(x: 20, y: 50, width: 170, height: 32)
                manual.view.backgroundColor = .clear
                controller.view.addSubview(manual.view)
                manual.didMove(toParent: controller)
                label.text = "NAME: TEST PERSON"
                field.text = "CARD: 0000-0000"
                image.image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50)).image { context in
                    UIColor.red.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
                    UIColor.blue.setFill()
                    context.fill(CGRect(x: 30, y: 10, width: 40, height: 30))
                }
                for view in [label, field, image] {
                    controller.view.addSubview(view)
                }
            }

            var views: [UIView] { [manual.view, label, field, image] }
        }

        private final class Harness {
            let server = MockPostHogServer()
            let sdk: PostHogSDK
            let integration = PostHogReplayIntegration()
            let window: UIWindow
            let root: UIViewController

            init(root: UIViewController) throws {
                let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                self.root = root
                window.rootViewController = root
                window.makeKeyAndVisible()
                root.view.frame = window.bounds
                server.start()
                let config = PostHogConfig(projectToken: "pr812_privacy", host: "http://localhost:9001")
                config.disableReachabilityForTesting = true
                config.disableQueueTimerForTesting = true
                config.disableFlushOnBackgroundForTesting = true
                config.disableRemoteConfigForTesting = true
                config.captureApplicationLifecycleEvents = false
                config.captureScreenViews = false
                config.sessionReplayConfig.maskAllTextInputs = true
                config.sessionReplayConfig.maskAllImages = true
                config.sessionReplayConfig.screenshotMode = true
                sdk = PostHogSDK.with(config)
                _ = integration.install(sdk)
                integration.stop()
            }

            func close() {
                integration.uninstall(sdk)
                sdk.close()
                server.stop()
                window.isHidden = true
                window.rootViewController = nil
            }

            func rects() throws -> [CGRect] {
                try #require(integration.collectMaskableRects(in: window))
            }

            func expectMasked(_ view: UIView, context: String = "") throws {
                let target = view.toPresentationRect(window).intersection(window.bounds).insetBy(dx: 3, dy: 3)
                try #require(!target.isEmpty, "Target must be on screen: \(context)")
                let regions = try rects()
                #expect(regions.contains { $0.insetBy(dx: -1, dy: -1).contains(target) },
                        "Visible PII must be masked (\(context)): target=\(target), masks=\(regions)")
            }

            func expectMasked(_ secrets: Secrets, context: String = "") throws {
                for view in secrets.views {
                    try expectMasked(view, context: "\(context) \(type(of: view))")
                }
            }
        }

        private func wait(_ condition: () -> Bool) async throws {
            for _ in 0 ..< 100 {
                try await Task.sleep(nanoseconds: 50_000_000)
                if condition() { return }
            }
            try #require(condition(), "UI did not settle")
        }

        private func settle(_ window: UIWindow) async throws {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        private func present(_ controller: UIViewController, over presenter: UIViewController,
                             in harness: Harness, style: UIModalPresentationStyle = .overFullScreen) async throws
        {
            controller.modalPresentationStyle = style
            presenter.present(controller, animated: false)
            try await wait { controller.viewIfLoaded?.window === harness.window && !controller.isBeingPresented }
            try await settle(harness.window)
        }

        @Test("normal screen: manual reporter, label, text input and dynamic image remain masked")
        func normalScreen() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            try await settle(h.window)
            try h.expectMasked(base)
        }

        @Test("secure fields and explicit masks work with global text and image masking disabled")
        func explicitAndSecureWithGlobalsDisabled() async throws {
            let base = Secrets()
            base.field.isSecureTextEntry = true
            let h = try Harness(root: base.controller)
            defer { h.close() }
            h.sdk.config.sessionReplayConfig.maskAllTextInputs = false
            h.sdk.config.sessionReplayConfig.maskAllImages = false
            try await settle(h.window)
            try h.expectMasked(base.manual.view)
            try h.expectMasked(base.field)
        }

        @Test("PII inside opaque covers remains masked", arguments: [false, true])
        func insideOpaqueCover(fullScreen: Bool) async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = Secrets()
            try await present(cover.controller, over: base.controller, in: h, style: fullScreen ? .fullScreen : .overFullScreen)
            try h.expectMasked(cover)
            cover.controller.dismiss(animated: false)
            try await wait { base.controller.presentedViewController == nil }
            try await settle(h.window)
            try h.expectMasked(base, context: "after dismissal")
        }

        @Test("medium sheet keeps visible presenter PII and sheet PII masked")
        @available(iOS 15.0, *)
        func mediumSheet() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let sheet = Secrets()
            sheet.controller.modalPresentationStyle = .pageSheet
            sheet.controller.sheetPresentationController?.detents = [.medium()]
            try await present(sheet.controller, over: base.controller, in: h, style: .pageSheet)
            let sheetRect = sheet.controller.view.toPresentationRect(h.window)
            try #require(sheetRect.minY > base.image.toPresentationRect(h.window).maxY)
            try h.expectMasked(base)
            try h.expectMasked(sheet)
        }

        @Test("partially translated cover keeps exposed presenter PII masked")
        func partialCover() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = Secrets()
            try await present(cover.controller, over: base.controller, in: h)
            cover.controller.view.transform = CGAffineTransform(translationX: 0, y: 350)
            try await settle(h.window)
            try #require(!cover.controller.view.toPresentationRect(h.window).contains(h.window.bounds))
            try h.expectMasked(base)
            try h.expectMasked(cover)
        }

        @Test("nested covers retain visible PII at both levels", arguments: [false, true])
        func nestedCovers(transparentTop: Bool) async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let middle = Secrets()
            try await present(middle.controller, over: base.controller, in: h)
            let top = Secrets(background: transparentTop ? .clear : .white)
            for view in top.views {
                view.frame.origin.x = 210
            }
            try await present(top.controller, over: middle.controller, in: h)
            try h.expectMasked(top)
            if transparentTop { try h.expectMasked(middle) }
            top.controller.dismiss(animated: false)
            try await wait { middle.controller.presentedViewController == nil }
            try await settle(h.window)
            try h.expectMasked(middle)
            middle.controller.dismiss(animated: false)
            try await wait { base.controller.presentedViewController == nil }
            try await settle(h.window)
            try h.expectMasked(base)
        }

        private final class SwiftUIModel: ObservableObject {
            @Published var presented = false
            var probes: [String: UIView] = [:]
        }

        private struct Probe: UIViewRepresentable {
            let model: SwiftUIModel
            let key: String
            func makeUIView(context _: Context) -> UIView {
                let view = UIView()
                model.probes[key] = view
                return view
            }
            func updateUIView(_: UIView, context _: Context) {}
        }

        @available(iOS 14.0, *)
        private struct SwiftUIScreen: View {
            @ObservedObject var model: SwiftUIModel
            var body: some View {
                Text("PRESENTER SECRET").postHogMask()
                    .fullScreenCover(isPresented: $model.presented) {
                        VStack(spacing: 30) {
                            Text("EXPLICIT SECRET").postHogMask().background(Probe(model: model, key: "manual"))
                            Text("NAME: TEST PERSON").background(Probe(model: model, key: "text"))
                            TextField("Card", text: .constant("0000-0000"))
                                .frame(width: 180).background(Probe(model: model, key: "input"))
                            Image(uiImage: UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
                                UIColor.red.setFill()
                                context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
                            }).background(Probe(model: model, key: "image"))
                        }
                    }
            }
        }

        @available(iOS 14.0, *)
        @Test("SwiftUI fullScreenCover masks its explicit text, automatic Text, TextField and Image")
        func swiftUISensitiveCover() async throws {
            let model = SwiftUIModel()
            let controller = UIHostingController(rootView: SwiftUIScreen(model: model))
            let h = try Harness(root: controller)
            defer { h.close() }
            try await settle(h.window)
            model.presented = true
            try await wait {
                guard let cover = controller.presentedViewController else { return false }
                return cover.viewIfLoaded?.window === h.window && !cover.isBeingPresented && model.probes.count == 4
            }
            try await settle(h.window)
            for (key, view) in model.probes {
                try h.expectMasked(view, context: "SwiftUI \(key)")
            }
            model.presented = false
            try await wait { controller.presentedViewController == nil }
        }

        @available(iOS 16.4, *)
        private struct TransparentSwiftUIScreen: View {
            @ObservedObject var model: SwiftUIModel

            var body: some View {
                VStack(spacing: 30) {
                    Text("MANUAL PRESENTER SECRET").postHogMask()
                        .background(Probe(model: model, key: "presenterManual"))
                    Text("AUTOMATIC PRESENTER SECRET")
                        .background(Probe(model: model, key: "presenterAutomatic"))
                }
                .fullScreenCover(isPresented: $model.presented) {
                    Text("COVER SECRET").postHogMask()
                        .background(Probe(model: model, key: "cover"))
                        .presentationBackground(.clear)
                }
            }
        }

        @available(iOS 16.4, *)
        @Test("transparent SwiftUI fullScreenCover retains presenter and cover masks")
        func transparentSwiftUIFullScreenCover() async throws {
            let model = SwiftUIModel()
            let controller = UIHostingController(rootView: TransparentSwiftUIScreen(model: model))
            let h = try Harness(root: controller)
            defer { h.close() }
            try await settle(h.window)
            let manual = try #require(model.probes["presenterManual"])
            let automatic = try #require(model.probes["presenterAutomatic"])
            try h.expectMasked(manual)
            try h.expectMasked(automatic)

            model.presented = true
            try await wait {
                guard let cover = controller.presentedViewController else { return false }
                return cover.viewIfLoaded?.window === h.window && !cover.isBeingPresented && model.probes["cover"] != nil
            }
            try await settle(h.window)
            try #require(controller.view.window === h.window)
            try h.expectMasked(manual, context: "manual presenter behind clear fullScreenCover")
            try h.expectMasked(automatic, context: "automatic presenter behind clear fullScreenCover")
            try h.expectMasked(try #require(model.probes["cover"]), context: "cover content")

            model.presented = false
            try await wait { controller.presentedViewController == nil }
            try await settle(h.window)
            try h.expectMasked(manual)
            try h.expectMasked(automatic)
        }

        @Test("animated slide presentation and dismissal preserve masks on exposed content")
        func slideTransitions() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = Secrets()
            cover.controller.modalPresentationStyle = .overFullScreen
            var samples = 0
            var completed = false
            base.controller.present(cover.controller, animated: true) { completed = true }
            while !completed {
                try await Task.sleep(nanoseconds: 20_000_000)
                guard cover.controller.viewIfLoaded?.window === h.window else { continue }
                let coverRect = cover.controller.view.toPresentationRect(h.window)
                if coverRect.minY > base.image.toPresentationRect(h.window).maxY {
                    try h.expectMasked(base, context: "presenting")
                    samples += 1
                }
            }
            try await settle(h.window)
            try h.expectMasked(cover)
            completed = false
            cover.controller.dismiss(animated: true) { completed = true }
            while !completed {
                try await Task.sleep(nanoseconds: 20_000_000)
                if cover.controller.viewIfLoaded?.window !== h.window ||
                    cover.controller.view.toPresentationRect(h.window).minY > base.image.toPresentationRect(h.window).maxY
                {
                    try h.expectMasked(base, context: "dismissing")
                    samples += 1
                }
            }
            try #require(samples > 0, "Must sample exposed PII during real transitions")
            try h.expectMasked(base)
        }

        @Test("fading out an explicit mask ancestor retains masking until visually transparent")
        func fadingReporterAncestor() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            try await settle(h.window)
            UIView.animate(withDuration: 2, delay: 0, options: .curveLinear) { base.manual.view.alpha = 0 }
            try await Task.sleep(nanoseconds: 300_000_000)
            let opacity = try #require(base.manual.view.layer.presentation()?.opacity)
            try #require(opacity > 0 && opacity < 1)
            try h.expectMasked(base.manual.view)
            try await wait { (base.manual.view.layer.presentation()?.opacity ?? 0) == 0 }
        }

        @Test("fading in an opaque cover keeps PII visible through it masked")
        func fadingCover() async throws {
            let base = Secrets(background: .yellow)
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            cover.view.alpha = 0
            try await settle(h.window)
            UIView.animate(withDuration: 2, delay: 0, options: .curveLinear) { cover.view.alpha = 1 }
            try await Task.sleep(nanoseconds: 300_000_000)
            let opacity = try #require(cover.view.layer.presentation()?.opacity)
            try #require(opacity > 0.05 && opacity < 0.8)
            try #require(base.controller.view.window === h.window)
            #expect(base.controller.transitionCoordinator == nil && cover.transitionCoordinator == nil)
            try h.expectMasked(base, context: "cover still translucent")
            try await wait { (cover.view.layer.presentation()?.opacity ?? 0) >= 1 }
        }

        @Test("translucent presentation ancestor does not suppress presenter PII masks")
        func translucentCoverAncestor() async throws {
            let base = Secrets(background: .yellow)
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            let container = try #require(cover.view.superview)
            try #require(container !== h.window && !base.controller.view.isDescendant(of: container))
            container.alpha = 0.3
            try await settle(h.window)
            try h.expectMasked(base)
        }

        @Test("rendered cover state must be safe, not just its animation destination",
              arguments: ["background", "rotation", "cornerRadius", "ancestorOpacity"])
        func animatedCoverState(property: String) async throws {
            let base = Secrets(background: .yellow)
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            let container = try #require(cover.view.superview)
            try #require(container !== h.window && !base.controller.view.isDescendant(of: container))
            let layer = property == "ancestorOpacity" ? container.layer : cover.view.layer
            switch property {
            case "background": cover.view.backgroundColor = .clear
            case "rotation": cover.view.transform = CGAffineTransform(rotationAngle: .pi / 12)
            case "cornerRadius": layer.cornerRadius = 100
            default: container.alpha = 0
            }
            try await settle(h.window)
            UIView.animate(withDuration: 2, delay: 0, options: .curveLinear) {
                switch property {
                case "background": cover.view.backgroundColor = .white
                case "rotation": cover.view.transform = .identity
                case "cornerRadius": layer.cornerRadius = 0
                default: container.alpha = 1
                }
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            let rendered = try #require(layer.presentation())
            switch property {
            case "background": try #require((rendered.backgroundColor?.alpha ?? 1) < 0.8)
            case "rotation": try #require(!CATransform3DIsIdentity(rendered.transform))
            case "cornerRadius": try #require(rendered.cornerRadius > 0)
            default: try #require(rendered.opacity > 0 && rendered.opacity < 0.8)
            }
            try h.expectMasked(base, context: "animated \(property)")
            try await wait { layer.animationKeys()?.isEmpty ?? true }
            try await settle(h.window)
            #expect(try h.rects().isEmpty, "Settled opaque cover must still remove stale masks")
        }

        @Test("a masked presentation ancestor keeps presenter PII masked")
        func maskedCoverAncestor() async throws {
            let base = Secrets(background: .yellow)
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            let container = try #require(cover.view.superview)
            try #require(container !== h.window && !base.controller.view.isDescendant(of: container))
            let mask = CAShapeLayer()
            mask.path = UIBezierPath(rect: CGRect(x: 200, y: 0, width: 200, height: h.window.bounds.height)).cgPath
            container.layer.mask = mask
            try await settle(h.window)
            try h.expectMasked(base)
        }

        @Test("a no-capture ancestor above a cover keeps the cover's own content masked")
        func noCaptureAncestorAboveCover() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            // The app marks the whole window sensitive, and a presentation stays inside that
            // subtree. The plain view carries nothing the heuristics can read, so the rule
            // inherited from the window is the only thing that can mask it.
            h.window.accessibilityIdentifier = "ph-no-capture"
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            let plain = UIView(frame: CGRect(x: 20, y: 100, width: 170, height: 32))
            plain.backgroundColor = .green
            cover.view.addSubview(plain)
            try await present(cover, over: base.controller, in: h)
            try h.expectMasked(plain, context: "no-capture window above the cover")
        }

        @Test("a no-mask ancestor above a cover keeps the heuristic masks off it")
        func noMaskAncestorAboveCover() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            // The opposite direction of the same inheritance: the app opts the window out of
            // heuristic masking, so the cover inside it is opted out too.
            h.window.accessibilityIdentifier = "ph-no-mask"
            let cover = Secrets()
            try await present(cover.controller, over: base.controller, in: h)
            let label = cover.label.toPresentationRect(h.window)
            try #require(!label.isEmpty)
            let regions = try h.rects()
            #expect(regions.allSatisfy { !$0.intersects(label) }, "no-mask must reach the cover: masks=\(regions)")
            // Explicit reporters are a separate source, which `ph-no-mask` never touched.
            try h.expectMasked(cover.manual.view, context: "explicit mask under a no-mask ancestor")
        }

        @Test("invisible siblings do not bring back stale masks", arguments: ["hidden", "transparent"], [false, true])
        func invisibleSibling(visibility: String, raised: Bool) async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let overlay = Secrets(background: .clear)
            let banner = try #require(overlay.controller.view)
            banner.frame = CGRect(x: 190, y: 300, width: 210, height: 300)
            if raised {
                banner.layer.zPosition = 100
                h.window.addSubview(banner)
            }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            if !raised { h.window.addSubview(banner) }
            try await settle(h.window)
            try h.expectMasked(overlay, context: "visible banner")

            if visibility == "hidden" {
                banner.isHidden = true
            } else {
                banner.alpha = 0
            }
            try await settle(h.window)
            #expect(try h.rects().isEmpty, "Invisible banner must not veto the opaque cover")

            banner.isHidden = false
            banner.alpha = 1
            try await settle(h.window)
            try h.expectMasked(overlay, context: "visible banner restored")
        }

        @Test("a fading sibling stays masked until its rendered opacity reaches zero")
        func fadingSibling() async throws {
            let base = Secrets()
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            let overlay = Secrets(background: .clear)
            let banner = try #require(overlay.controller.view)
            banner.frame = CGRect(x: 190, y: 300, width: 210, height: 300)
            h.window.addSubview(banner)
            try await settle(h.window)
            try h.expectMasked(overlay)
            UIView.animate(withDuration: 2, delay: 0, options: .curveLinear) { banner.alpha = 0 }
            try await Task.sleep(nanoseconds: 300_000_000)
            let renderedOpacity = try #require(banner.layer.presentation()?.opacity)
            try #require(renderedOpacity > 0 && renderedOpacity < 1)
            try h.expectMasked(overlay, context: "banner still fading")
            try await wait { (banner.layer.presentation()?.opacity ?? banner.layer.opacity) == 0 }
            #expect(try h.rects().isEmpty, "Fully faded banner must not veto the opaque cover")
        }

        @Test("rotated cover bounding box is not proof the presenter is hidden")
        func rotatedCover() async throws {
            let base = Secrets(background: .yellow)
            let h = try Harness(root: base.controller)
            defer { h.close() }
            let cover = UIViewController()
            cover.view.backgroundColor = .white
            try await present(cover, over: base.controller, in: h)
            cover.view.transform = CGAffineTransform(rotationAngle: .pi / 12)
            try await settle(h.window)
            try #require(cover.view.toPresentationRect(h.window).contains(h.window.bounds))
            let point = CGPoint(x: 25, y: 110)
            try #require(!cover.view.bounds.contains(cover.view.convert(point, from: h.window)))
            try h.expectMasked(base.label, context: "left of rotated cover")
        }
    }
#endif
