#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    private final class GlassBackdropView: UIView {
        override class var layerClass: AnyClass { NSClassFromString("CABackdropLayer") ?? CALayer.self }
    }

    private final class GlassSDFView: UIView {
        override class var layerClass: AnyClass { NSClassFromString("CASDFLayer") ?? CALayer.self }
    }

    private final class GlassShapeView: UIView {
        override class var layerClass: AnyClass { NSClassFromString("CASDFElementLayer") ?? CALayer.self }
    }

    private final class MetalView: UIView {
        override class var layerClass: AnyClass { CAMetalLayer.self }
    }

    @Suite("Replay GPU capture", .serialized)
    @MainActor
    struct PostHogGPUCaptureTest {
        private struct RGBA: Equatable {
            let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

            static let magenta = RGBA(red: 255, green: 0, blue: 255, alpha: 255)
            static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
            static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
            static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
        }

        /// RGBA8 pixels, 1x.
        private struct Pixels {
            let width: Int
            let height: Int
            private let bytes: [UInt8]

            init(_ image: CGImage) throws {
                width = image.width
                height = image.height
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let context = try #require(CGContext(
                    data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                self.bytes = bytes
            }

            subscript(x: Int, y: Int) -> RGBA {
                let index = (y * width + x) * 4
                return RGBA(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
            }

            func points(where predicate: (RGBA) -> Bool) -> [CGPoint] {
                var points: [CGPoint] = []
                for y in 0 ..< height {
                    for x in 0 ..< width where predicate(self[x, y]) {
                        points.append(CGPoint(x: x, y: y))
                    }
                }
                return points
            }
        }

        private static func isMagenta(_ pixel: RGBA) -> Bool {
            pixel.red > 200 && pixel.green < 60 && pixel.blue > 200
        }

        private func makeMirror() throws -> PostHogGPUMirrorCapture {
            // Its own instance per test, so no renderer or frame carries over between tests.
            try #require(PostHogGPUMirrorCapture(), "the simulator has no Metal device")
        }

        private func makeWindow(background: UIColor = .white) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.backgroundColor = background
            // Shown without becoming key, so the SDK's own capture loop never picks it up.
            window.isHidden = false
            return window
        }

        private func prewarm(_ mirror: PostHogGPUMirrorCapture, for window: UIWindow, scale: CGFloat = 1) async {
            await withCheckedContinuation { continuation in
                mirror.prewarm(size: window.bounds.size, scale: scale) { continuation.resume() }
            }
        }

        /// Turn 1 and turn 2 of a capture, without the replay pipeline around them: the pixels and the mask rects.
        private func render(_ window: UIWindow, with mirror: PostHogGPUMirrorCapture, scale: CGFloat = 1) async throws -> (CGImage, [CGRect]) {
            window.layoutIfNeeded()
            let frame = try #require(mirror.build(window: window, scale: scale))
            #expect(frame.scale == scale)
            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window, culledLayers: frame.culledLayers,
                                                                                     portalSources: frame.portalSources))
            frame.freeze()
            #expect(frame.encode())
            let image = await withCheckedContinuation { continuation in
                frame.readback(on: .global()) { continuation.resume(returning: $0) }
            }
            frame.release()
            return try (#require(image), rects)
        }

        private func noCaptureView(_ frame: CGRect, color: UIColor = .magenta) -> UIView {
            let view = UIView(frame: frame)
            view.backgroundColor = color
            view.accessibilityIdentifier = "ph-no-capture"
            return view
        }

        // MARK: - Mask walk

        @Test("The mask walk skips exactly the subtrees the mirror left out of the frame")
        func maskWalkSkipsOnlyCulledSubtrees() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let visible = noCaptureView(CGRect(x: 10, y: 10, width: 40, height: 40))
            let partlyVisible = noCaptureView(CGRect(x: 180, y: 60, width: 40, height: 40))

            let clipper = UIView(frame: CGRect(x: 10, y: 120, width: 60, height: 60))
            clipper.clipsToBounds = true
            let clippedAway = noCaptureView(CGRect(x: 100, y: 0, width: 40, height: 40))
            clipper.addSubview(clippedAway)

            let farAway = noCaptureView(CGRect(x: 10, y: 5000, width: 40, height: 40))

            for view in [visible, partlyVisible, clipper, farAway] {
                window.addSubview(view)
            }
            window.layoutIfNeeded()

            let frame = try #require(mirror.build(window: window, scale: 1))
            defer { frame.release() }
            let integration = PostHogReplayIntegration()
            let unculled = try #require(integration.collectMaskableRects(in: window))
            let culled = try #require(integration.collectMaskableRects(in: window, culledLayers: frame.culledLayers))

            #expect(frame.culledLayers.contains(ObjectIdentifier(clippedAway.layer)))
            #expect(frame.culledLayers.contains(ObjectIdentifier(farAway.layer)))
            #expect(!frame.culledLayers.contains(ObjectIdentifier(visible.layer)))
            #expect(!frame.culledLayers.contains(ObjectIdentifier(partlyVisible.layer)))

            let visibleRects = [visible.frame, partlyVisible.frame]
            let culledRects = [clippedAway.convert(clippedAway.bounds, to: window), farAway.frame]
            #expect(Set(unculled.map(NSCoder.string(for:))) == Set((visibleRects + culledRects).map(NSCoder.string(for:))))
            #expect(Set(culled.map(NSCoder.string(for:))) == Set(visibleRects.map(NSCoder.string(for:))))
        }

        // MARK: - Pixels

        @Test("Mask rects line up with the mirrored pixels at each output scale, and masking covers them", arguments: [1, 0.5] as [CGFloat])
        func maskRectsCoverMirroredPixels(scale: CGFloat) async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window, scale: scale)

            let marker = UIView(frame: CGRect(x: 120, y: 20, width: 30, height: 30))
            marker.backgroundColor = .blue
            let moved = UIView(frame: CGRect(x: 10, y: 100, width: 150, height: 150))
            moved.bounds.origin = CGPoint(x: 5, y: 10)
            moved.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            // Inset inside its masked field, as text is: masks are drawn with rounded corners.
            let field = noCaptureView(CGRect(x: 30, y: 40, width: 60, height: 50), color: .clear)
            let secret = UIView(frame: field.bounds.insetBy(dx: 5, dy: 5))
            secret.backgroundColor = .magenta
            field.addSubview(secret)
            moved.addSubview(field)
            window.addSubview(marker)
            window.addSubview(moved)

            let (image, rects) = try await render(window, with: mirror, scale: scale)
            let pixels = try Pixels(image)
            #expect(pixels.width == Int((200 * scale).rounded(.up)))
            #expect(pixels.height == Int((300 * scale).rounded(.up)))
            let fieldRect = field.convert(field.bounds, to: window)
            #expect(rects.contains(fieldRect))

            func pixel(_ x: CGFloat, _ y: CGFloat) -> RGBA {
                pixels[Int(x * scale), Int(y * scale)]
            }

            // Upright and in place: the marker sits where UIKit lays it out.
            #expect(pixel(135, 35) == .blue)
            #expect(pixel(135, 265) == .white)

            let magenta = pixels.points(where: Self.isMagenta)
            #expect(!magenta.isEmpty)
            let secretRect = secret.convert(secret.bounds, to: window)
            let covering = secretRect.insetBy(dx: -1 / scale, dy: -1 / scale)
            #expect(magenta.allSatisfy { covering.contains(CGPoint(x: ($0.x + 0.5) / scale, y: ($0.y + 0.5) / scale)) })
            let inner = secretRect.insetBy(dx: 1 / scale, dy: 1 / scale)
            #expect(Self.isMagenta(pixel(inner.midX, inner.midY)))
            #expect(Self.isMagenta(pixel(inner.minX, inner.minY)))
            #expect(Self.isMagenta(pixel(inner.maxX - 1 / scale, inner.maxY - 1 / scale)))

            let uiImage = UIImage(cgImage: image, scale: scale, orientation: .up)
            let maskedImage = try #require(RRWireframe.maskImage(uiImage, maskableWidgets: rects, scale: scale)?.cgImage)
            let masked = try Pixels(maskedImage)
            #expect(masked.width == pixels.width && masked.height == pixels.height)
            #expect(masked.points(where: Self.isMagenta).isEmpty)
        }

        @available(iOS 26.0, *)
        @Test("Corners UIKit rounds per corner, leaving cornerRadius at 0, are rounded in the copy")
        func perCornerRadiiAreCopied() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let card = UIView(frame: CGRect(x: 20, y: 20, width: 120, height: 80))
            card.backgroundColor = .blue
            card.cornerConfiguration = .corners(radius: .fixed(30))
            window.addSubview(card)
            #expect(card.layer.cornerRadius == 0)

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[22, 22] == .white)
            #expect(pixels[137, 97] == .white)
            #expect(pixels[80, 60] == .blue)
            #expect(pixels[80, 21] == .blue)
        }

        @Test("A NaN corner radius, UIKit's capsule, is drawn as a capsule")
        func nanCornerRadiusIsCapsule() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let platter = CALayer()
            platter.frame = CGRect(x: 20, y: 100, width: 160, height: 60)
            platter.backgroundColor = UIColor.blue.cgColor
            platter.cornerRadius = .nan
            window.layer.addSublayer(platter)

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[100, 130] == .blue)
            #expect(pixels[22, 102] == .white)
            #expect(pixels[177, 157] == .white)
            #expect(pixels[100, 101] == .blue)
        }

        @Test("Template images keep their tint in the copy")
        func templateImagesKeepTheirTint() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let symbol = UIImage(systemName: "square.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40))
            let imageView = UIImageView(image: symbol)
            imageView.tintColor = .red
            imageView.contentMode = .center
            imageView.frame = CGRect(x: 20, y: 20, width: 160, height: 160)
            window.addSubview(imageView)

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[100, 100] == .red)
            // Centred at its own size, not stretched to the view.
            #expect(pixels[25, 25] == .white)
            #expect(pixels[175, 175] == .white)
        }

        /// The shape Liquid Glass builds: a backdrop with the glass background filter over a signed-distance-field shape.
        /// Built from the private classes because UIKit only builds real glass in a window with a scene.
        private func makeGlass(frame: CGRect, cornerRadius: CGFloat, filter: String) throws -> CALayer {
            let backdropClass = try #require(NSClassFromString("CABackdropLayer") as? CALayer.Type)
            let shapeClass = try #require(NSClassFromString("CASDFElementLayer") as? CALayer.Type)
            let filterClass: AnyObject = try #require(NSClassFromString("CAFilter"))
            let glassFilter = try #require(filterClass.perform(NSSelectorFromString("filterWithType:"), with: filter)?.takeUnretainedValue())
            let backdrop = backdropClass.init()
            backdrop.frame = frame
            backdrop.filters = [glassFilter]
            backdrop.setValue(true, forKey: "tracksLuma")
            backdrop.setValue(6, forKey: "marginWidth")
            let shape = shapeClass.init()
            shape.frame = backdrop.bounds
            shape.cornerRadius = cornerRadius
            backdrop.addSublayer(shape)
            return backdrop
        }

        /// Glass without luminance tracking or a sampling margin, over a shape whose output range ends at
        /// `outputMaximum`: a sheet's when that's tens of points, clear glass's when it's 1.
        private func makeUntrackedGlass(frame: CGRect, outputMaximum: Double) throws -> CALayer {
            let backdrop = try makeGlass(frame: frame, cornerRadius: 20, filter: "glassBackground")
            backdrop.setValue(false, forKey: "tracksLuma")
            backdrop.setValue(0, forKey: "marginWidth")
            let sdfClass = try #require(NSClassFromString("CASDFLayer") as? CALayer.Type)
            let outputClass = try #require(NSClassFromString("CASDFOutputEffect") as? NSObject.Type)
            let output = outputClass.init()
            output.setValue(outputMaximum, forKey: "maximum")
            let sdf = sdfClass.init()
            sdf.frame = backdrop.bounds
            sdf.setValue(output, forKey: "effect")
            sdf.sublayers = backdrop.sublayers
            backdrop.sublayers = [sdf]
            return backdrop
        }

        @Test("A sheet's glass, which shares clear glass's zero margin, fills like regular glass, not clear")
        func sheetGlassIsNotClear() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .red)
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeUntrackedGlass(frame: CGRect(x: 20, y: 40, width: 160, height: 80), outputMaximum: 34))
            window.layer.addSublayer(try makeUntrackedGlass(frame: CGRect(x: 20, y: 160, width: 160, height: 80), outputMaximum: 1))

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[100, 80].green > 200)
            #expect(pixels[100, 200].green < 120)
        }

        @Test("Panel-sized glass (sheets, alerts) draws as a blurred, colour-matrixed backdrop; control-sized keeps the flat fill")
        func panelGlassDrawsAsBackdropMaterial() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .green)
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 10, y: 10, width: 180, height: 150), cornerRadius: 20, filter: "glassBackground"))
            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 20, y: 200, width: 160, height: 60), cornerRadius: 30, filter: "glassBackground"))

            let pixels = try await Pixels(render(window, with: mirror).0)
            // The material maps green to about (118, 255, 127); 0.6 white over green would be (153, 255, 153).
            let panel = pixels[100, 85]
            #expect((100 ... 135).contains(panel.red) && panel.green > 235 && (110 ... 140).contains(panel.blue), "\(panel)")
            // Rounded like the shape.
            #expect(pixels[11, 11] == RGBA(red: 0, green: 255, blue: 0, alpha: 255))
            // 0.85 white over green.
            let control = pixels[100, 230]
            #expect(control.red > 200 && control.blue > 200)
        }

        @Test("Light panel glass over a light grey comes out a lighter grey, as on screen, not white")
        func lightPanelGlassOverGreyIsNotWhite() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: UIColor(white: 0.8, alpha: 1))
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 10, y: 10, width: 180, height: 150), cornerRadius: 20, filter: "glassBackground"))

            // iOS 26 draws a sheet over a dimmed white page (204) at about 236.
            let panel = try await Pixels(render(window, with: mirror).0)[100, 85]
            #expect([panel.red, panel.green, panel.blue].allSatisfy { (226 ... 246).contains($0) }, "\(panel)")
        }

        @Test("Panel glass at the edge of the window keeps its colour up to the edge instead of fading")
        func panelGlassAtWindowEdgeDoesNotFade() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .green)
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 0, y: 10, width: 180, height: 150), cornerRadius: 20, filter: "glassBackground"))

            let pixels = try await Pixels(render(window, with: mirror).0)
            let interior = pixels[100, 85]
            let edge = pixels[1, 85]
            let difference = [(edge.red, interior.red), (edge.green, interior.green), (edge.blue, interior.blue)]
                .map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0
            #expect(difference <= 4, "edge \(edge) vs interior \(interior)")
        }

        @Test("Untinted glass controls in dark mode read as dark grey over black, not black")
        func darkGlassControlIsDarkGrey() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .black)
            window.overrideUserInterfaceStyle = .dark
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 20, y: 100, width: 160, height: 60), cornerRadius: 30, filter: "glassBackground"))

            // iOS 26 draws regular glass over black at about (19, 19, 19) to (25, 25, 25).
            let pixel = try await Pixels(render(window, with: mirror).0)[100, 130]
            #expect((15 ... 30).contains(pixel.red) && pixel.red == pixel.green && pixel.green == pixel.blue, "\(pixel)")
        }

        @Test("Untinted dark glass in a bar reads lighter than on a button, as iOS 26 draws it")
        func darkGlassInBarIsLighterThanButton() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .black)
            window.overrideUserInterfaceStyle = .dark
            await prewarm(mirror, for: window)

            final class FloatingBarContainer: UIView {}
            let bar = FloatingBarContainer(frame: CGRect(x: 20, y: 200, width: 160, height: 60))
            bar.addSubview(try makeGlassGroup(frame: bar.bounds, tinted: false))
            window.addSubview(bar)
            window.addSubview(try makeGlassGroup(frame: CGRect(x: 20, y: 100, width: 160, height: 60), tinted: false))

            // iOS 26 over black: about 25 for a tab bar platter or bar item, 19 for a glass button.
            let pixels = try await Pixels(render(window, with: mirror).0)
            let barPixel = pixels[100, 230], buttonPixel = pixels[100, 130]
            #expect((24 ... 30).contains(barPixel.red), "\(barPixel)")
            #expect((18 ... 23).contains(buttonPixel.red), "\(buttonPixel)")
        }

        @Test("Glass without a view of its own (SwiftUI) takes dark mode from the nearest view above it")
        func darkPanelGlassUsesDarkMaterial() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .green)
            window.overrideUserInterfaceStyle = .dark
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 10, y: 10, width: 180, height: 150), cornerRadius: 20, filter: "glassBackground"))

            // The dark material maps green to about (0, 127, 0); the light one would brighten it.
            let panel = try await Pixels(render(window, with: mirror).0)[100, 85]
            #expect(panel.red < 20 && (115 ... 140).contains(panel.green) && panel.blue < 20)
        }

        @Test("Liquid Glass draws as a flat translucent fill in its shape instead of nothing")
        func liquidGlassDrawsAsFlatFill() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .red)
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 20, y: 100, width: 160, height: 60), cornerRadius: 30,
                                                   filter: "glassBackground"))
            // Other backdrops keep their own rendering and get no fill.
            window.layer.addSublayer(try makeGlass(frame: CGRect(x: 20, y: 200, width: 160, height: 60), cornerRadius: 30,
                                                   filter: "gaussianBlur"))

            let pixels = try await Pixels(render(window, with: mirror).0)
            let inside = pixels[100, 130]
            #expect(inside.red > 200 && inside.green > 150 && inside.blue > 150)
            // Rounded like the shape: the frame's corner stays outside it.
            #expect(pixels[21, 101] == .red)
            #expect(pixels[10, 130] == .red)
            #expect(pixels[100, 230].green < 60)
        }

        /// UIKit's glass built from views, so the shape can find the control that owns it: a group holding a material
        /// with the glass background over the shape and, for tinted glass, a sibling layer composited `destIn`.
        /// `untintedShapes` share the group, as a toolbar's plain buttons share it with a tinted one: the tint layer keeps
        /// their outlines hidden.
        private func makeGlassGroup(frame: CGRect, tinted: Bool, tintMatrix: [Float]? = nil, tintedShape: CGRect? = nil,
                                    untintedShapes: [CGRect] = []) throws -> UIView
        {
            let filterClass: AnyObject = try #require(NSClassFromString("CAFilter"))
            let glassFilter = try #require(filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?.takeUnretainedValue())
            let group = UIView(frame: frame)
            let material = UIView(frame: group.bounds)
            let backdrop = GlassBackdropView(frame: group.bounds)
            backdrop.layer.filters = [glassFilter]
            backdrop.layer.setValue(true, forKey: "tracksLuma")
            backdrop.layer.setValue(6, forKey: "marginWidth")
            let tintedFrame = tintedShape ?? group.bounds
            for shapeFrame in [tintedFrame] + untintedShapes {
                let shape = GlassShapeView(frame: shapeFrame)
                shape.layer.cornerRadius = shapeFrame.height / 2
                backdrop.addSubview(shape)
            }
            material.addSubview(backdrop)
            group.addSubview(material)
            if tinted {
                // The tint is a gradient shape drawn through the colour matrix; the shape it's cut to is composited `destIn`.
                let tintMaterial = GlassSDFView(frame: group.bounds)
                let gradientClass = try #require(NSClassFromString("CASDFGradientEffect") as? NSObject.Type)
                tintMaterial.layer.setValue(gradientClass.init(), forKey: "effect")
                let tintCutout = UIView(frame: group.bounds)
                tintCutout.layer.compositingFilter = "destIn"
                for shapeFrame in [tintedFrame] + untintedShapes {
                    let outline = GlassShapeView(frame: shapeFrame)
                    outline.isHidden = shapeFrame != tintedFrame
                    tintCutout.addSubview(outline)
                }
                tintMaterial.addSubview(tintCutout)
                if var tintMatrix {
                    let matrixFilter = try #require(filterClass.perform(NSSelectorFromString("filterWithType:"), with: "vibrantColorMatrix")?
                        .takeUnretainedValue() as? NSObject)
                    let value = NSValue(bytes: &tintMatrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
                    matrixFilter.setValue(value, forKey: "inputColorMatrix")
                    tintMaterial.layer.filters = [matrixFilter]
                }
                group.addSubview(tintMaterial)
            }
            return group
        }

        @Test("Tinted glass takes the tint its material's colour matrix gives the light background, before any owner's tint")
        func tintedGlassTakesMaterialTint() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            // Luminance weights scaled per channel plus offsets, as SwiftUI builds `.glassEffect(.regular.tint(.orange))`:
            // white maps to (1, 0.5, 0).
            let orange: [Float] = [0.06, 0.2, 0.02, 0, 0.72,
                                   0.05, 0.15, 0.0, 0, 0.3,
                                   0, 0, 0, 0, 0,
                                   0, 0, 0, 1, 0]
            let button = UIButton(type: .custom)
            button.frame = CGRect(x: 20, y: 100, width: 160, height: 60)
            button.tintColor = .blue
            button.addSubview(try makeGlassGroup(frame: button.bounds, tinted: true, tintMatrix: orange))
            window.addSubview(button)

            let pixel = try await Pixels(render(window, with: mirror).0)[100, 130]
            #expect(pixel.red > 245 && (118 ... 137).contains(pixel.green) && pixel.blue < 10)
        }

        @Test("In dark mode the tint is what the colour matrix gives the dark background, not white")
        func darkTintedGlassAppliesMatrixToDarkBackground() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            window.overrideUserInterfaceStyle = .dark
            await prewarm(mirror, for: window)

            // iOS 26's dark prominent-glass blue: black maps to (0, 0.559, 1), white to a lighter (0.17, 0.63, 0.97).
            let blue: [Float] = [0.043, 0.146, 0.015, 0, -0.031,
                                 0.014, 0.048, 0.005, 0, 0.559,
                                 -0.008, -0.027, -0.003, 0, 1.006,
                                 0, 0, 0, 1, 0]
            let button = UIButton(type: .custom)
            button.frame = CGRect(x: 20, y: 100, width: 160, height: 60)
            button.addSubview(try makeGlassGroup(frame: button.bounds, tinted: true, tintMatrix: blue))
            window.addSubview(button)

            let pixel = try await Pixels(render(window, with: mirror).0)[100, 130]
            #expect(pixel.red < 10 && (135 ... 150).contains(pixel.green) && pixel.blue > 245)
        }

        @Test("Only the glass shapes the tint layer outlines are tinted, when one group holds several")
        func sharedGlassGroupTintsOnlyItsTintedShape() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .red)
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            let blue: [Float] = [0, 0, 0, 0, 0,
                                 0, 0, 0, 0, 0,
                                 0, 0, 0, 0, 1,
                                 0, 0, 0, 1, 0]
            let group = try makeGlassGroup(frame: CGRect(x: 10, y: 100, width: 180, height: 60), tinted: true, tintMatrix: blue,
                                           tintedShape: CGRect(x: 100, y: 0, width: 80, height: 60),
                                           untintedShapes: [CGRect(x: 0, y: 0, width: 60, height: 60)])
            window.addSubview(group)

            let pixels = try await Pixels(render(window, with: mirror).0)
            let plain = pixels[40, 130], tinted = pixels[150, 130]
            #expect(plain.red > 230 && plain.green > 190 && plain.blue > 190)
            #expect(tinted.red < 20 && tinted.green < 20 && tinted.blue > 230)
        }

        private static func isGrey(_ pixel: RGBA) -> Bool {
            max(pixel.red, pixel.green, pixel.blue) - min(pixel.red, pixel.green, pixel.blue) < 20 && (90 ... 200).contains(pixel.red)
        }

        @Test("Tinted glass takes the tint of the button it belongs to")
        func tintedGlassTakesButtonTint() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            let button = UIButton(type: .custom)
            button.frame = CGRect(x: 20, y: 100, width: 160, height: 60)
            button.tintColor = .red
            button.addSubview(try makeGlassGroup(frame: button.bounds, tinted: true))
            window.addSubview(button)

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[100, 130] == .red)
        }

        @available(iOS 15.0, *)
        @Test("Glass with a white label, or tinted with no tint to read, is grey so its label still reads")
        func untintableGlassContrastsWithItsLabel() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            window.overrideUserInterfaceStyle = .light
            await prewarm(mirror, for: window)

            window.addSubview(try makeGlassGroup(frame: CGRect(x: 20, y: 20, width: 160, height: 60), tinted: true))
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = .white
            let button = UIButton(configuration: configuration)
            button.frame = CGRect(x: 20, y: 100, width: 160, height: 60)
            button.addSubview(try makeGlassGroup(frame: button.bounds, tinted: false))
            window.addSubview(button)
            // Plain glass with a dark label keeps the light fill.
            window.addSubview(try makeGlassGroup(frame: CGRect(x: 20, y: 200, width: 160, height: 60), tinted: false))

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(Self.isGrey(pixels[100, 50]))
            #expect(Self.isGrey(pixels[100, 130]))
            #expect(pixels[100, 230].red > 230 && pixels[100, 230].green > 230)
        }

        @Test("Tinted-image contents, which SwiftUI draws text on glass into, are shared with the copy")
        func tintedImageContentsAreShared() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let image = try #require(context.makeImage())
            let tintedImageClass: AnyObject = try #require(NSClassFromString("CATintedImage"))
            let tinted = try #require(tintedImageClass.perform(NSSelectorFromString("tintedImageWithCGImage:tint:"), with: image,
                                                               with: UIColor.red.cgColor)?.takeUnretainedValue())
            let layer = CALayer()
            layer.frame = CGRect(x: 20, y: 20, width: 100, height: 100)
            layer.contents = tinted
            window.layer.addSublayer(layer)

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[70, 70] != .white)
            #expect(pixels[150, 150] == .white)
        }

        // MARK: - Portals

        private func makePortal(showing source: CALayer, frame: CGRect, matchesPosition: Bool = true, matchesTransform: Bool = true,
                                sourceContextId: UInt32 = 0, hidesSource: Bool = true) throws -> CALayer
        {
            let portalClass = try #require(NSClassFromString("CAPortalLayer") as? CALayer.Type)
            let portal = portalClass.init()
            portal.frame = frame
            portal.masksToBounds = true
            portal.setValue(source, forKey: "sourceLayer")
            portal.setValue(hidesSource, forKey: "hidesSourceLayer")
            portal.setValue(matchesPosition, forKey: "matchesPosition")
            portal.setValue(matchesTransform, forKey: "matchesTransform")
            portal.setValue(sourceContextId, forKey: "sourceContextId")
            return portal
        }

        private func count(_ pixels: Pixels, in rect: CGRect, where predicate: (RGBA) -> Bool) -> Int {
            var count = 0
            for y in Int(rect.minY) ..< Int(rect.maxY) {
                for x in Int(rect.minX) ..< Int(rect.maxX) where predicate(pixels[x, y]) {
                    count += 1
                }
            }
            return count
        }

        @Test("A matched portal draws a source clipped away where it sits, and the source stays masked")
        func matchedPortalContentStaysMasked() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            // The secret sits outside its clipping parent, so nothing of it shows where it sits.
            let clipper = UIView(frame: CGRect(x: 10, y: 200, width: 40, height: 40))
            clipper.clipsToBounds = true
            // Inset inside its masked field, as text is: masks are drawn with rounded corners.
            let field = noCaptureView(CGRect(x: 10, y: -150, width: 120, height: 60), color: .clear)
            let secret = UIView(frame: field.bounds.insetBy(dx: 5, dy: 5))
            secret.backgroundColor = .magenta
            field.addSubview(secret)
            clipper.addSubview(field)
            window.addSubview(clipper)
            let fieldRect = field.convert(field.bounds, to: window)
            let secretRect = secret.convert(secret.bounds, to: window)
            window.layer.addSublayer(try makePortal(showing: field.layer, frame: fieldRect))
            window.layoutIfNeeded()

            let frame = try #require(mirror.build(window: window, scale: 1))
            #expect(frame.culledLayers.contains(ObjectIdentifier(field.layer)))
            #expect(frame.portalSources.contains { $0.view === field && $0.elsewhere == nil })
            frame.release()

            let (image, rects) = try await render(window, with: mirror)
            let pixels = try Pixels(image)
            #expect(count(pixels, in: secretRect, where: Self.isMagenta) > Int(secretRect.width * secretRect.height) * 9 / 10)
            #expect(rects.contains(fieldRect))

            let masked = try Pixels(#require(RRWireframe.maskImage(UIImage(cgImage: image), maskableWidgets: rects, scale: 1)?.cgImage))
            #expect(masked.points(where: Self.isMagenta).isEmpty)
        }

        @Test("A matched portal that hides its source leaves the source out where the portal doesn't show it")
        func hidingPortalLeavesSourceOut() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let source = UIView(frame: CGRect(x: 20, y: 100, width: 120, height: 60))
            source.backgroundColor = .blue
            window.addSubview(source)
            // Over the left half only.
            window.layer.addSublayer(try makePortal(showing: source.layer, frame: CGRect(x: 20, y: 100, width: 60, height: 60)))

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[50, 130] == .blue)
            #expect(pixels[110, 130] == .white)
        }

        @Test("A source shown by two matched portals is drawn by each")
        func sourceSharedByTwoPortals() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let source = UIView(frame: CGRect(x: 20, y: 100, width: 120, height: 60))
            source.backgroundColor = .blue
            window.addSubview(source)
            window.layer.addSublayer(try makePortal(showing: source.layer, frame: CGRect(x: 20, y: 100, width: 40, height: 60)))
            window.layer.addSublayer(try makePortal(showing: source.layer, frame: CGRect(x: 100, y: 100, width: 40, height: 60)))

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(pixels[40, 130] == .blue)
            #expect(pixels[120, 130] == .blue)
            #expect(pixels[80, 130] == .white)
        }

        @Test("Portals that don't show their source in place, or show another context's, stay out of the frame",
              arguments: [(false, true, 0), (true, false, 0), (true, true, 7), (false, false, 7)] as [(Bool, Bool, UInt32)])
        func unmatchedPortalsStayOut(matchesPosition: Bool, matchesTransform: Bool, sourceContextId: UInt32) async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let secret = noCaptureView(CGRect(x: 20, y: 20, width: 60, height: 40))
            window.addSubview(secret)
            let portalRect = CGRect(x: 100, y: 200, width: 60, height: 40)
            let portal = try makePortal(showing: secret.layer, frame: portalRect, matchesPosition: matchesPosition,
                                        matchesTransform: matchesTransform, sourceContextId: sourceContextId, hidesSource: false)
            #expect((portal.value(forKey: "sourceContextId") as? NSNumber)?.uint32Value == sourceContextId)
            window.layer.addSublayer(portal)

            let frame = try #require(mirror.build(window: window, scale: 1))
            #expect(frame.portalSources.isEmpty)
            frame.release()

            let pixels = try await Pixels(render(window, with: mirror).0)
            #expect(count(pixels, in: portalRect, where: Self.isMagenta) == 0)
            #expect(Self.isMagenta(pixels[50, 40]))
        }

        /// A portal that shows its source at its own position, as SwiftUI's glass shows its text: the source's bounds
        /// land on the portal's.
        private func makeLensPortal(showing source: UIView, frame: CGRect) throws -> CALayer {
            try makePortal(showing: source.layer, frame: frame, matchesPosition: false, matchesTransform: false)
        }

        private func maskedPixels(_ image: CGImage, _ rects: [CGRect]) throws -> Pixels {
            try Pixels(#require(RRWireframe.maskImage(UIImage(cgImage: image), maskableWidgets: rects, scale: 1)?.cgImage))
        }

        @Test("A lens portal draws its source on the portal, and masked text in it is masked there and where it sits")
        func lensPortalMovesItsMasks() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let source = UIView(frame: CGRect(x: 20, y: 20, width: 120, height: 60))
            let field = noCaptureView(CGRect(x: 10, y: 10, width: 100, height: 40), color: .clear)
            let secret = UIView(frame: field.bounds.insetBy(dx: 5, dy: 5))
            secret.backgroundColor = .magenta
            field.addSubview(secret)
            source.addSubview(field)
            window.addSubview(source)
            let portalRect = CGRect(x: 40, y: 180, width: 120, height: 60)
            window.layer.addSublayer(try makeLensPortal(showing: source, frame: portalRect))

            let (image, rects) = try await render(window, with: mirror)
            let pixels = try Pixels(image)
            // Hidden where it sits, drawn on the portal at the field's offset in the source.
            #expect(count(pixels, in: CGRect(x: 35, y: 35, width: 90, height: 30), where: Self.isMagenta) == 0)
            #expect(count(pixels, in: CGRect(x: 55, y: 195, width: 90, height: 30), where: Self.isMagenta) > 90 * 30 * 9 / 10)
            #expect(rects.contains(CGRect(x: 50, y: 190, width: 100, height: 40)))

            #expect(try maskedPixels(image, rects).points(where: Self.isMagenta).isEmpty)
        }

        @Test("A lens portal over a source with no masked views draws it on the portal, unmasked")
        func lensPortalDrawsUnmaskedContent() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let source = UIView(frame: CGRect(x: 20, y: 20, width: 120, height: 60))
            let label = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 40))
            label.backgroundColor = .blue
            source.addSubview(label)
            window.addSubview(source)
            window.layer.addSublayer(try makeLensPortal(showing: source, frame: CGRect(x: 40, y: 180, width: 120, height: 60)))

            let (image, rects) = try await render(window, with: mirror)
            #expect(rects.isEmpty)
            let pixels = try Pixels(image)
            #expect(pixels[100, 210] == .blue)
            #expect(pixels[60, 50] == .white)
        }

        @Test("A postHogMask reporter under a lens portal's source masks the whole portal")
        func lensPortalWithReporterMasksWholePortal() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let source = UIView(frame: CGRect(x: 20, y: 20, width: 120, height: 60))
            let reporter = PostHogMaskReporterUIView(frame: CGRect(x: 10, y: 10, width: 30, height: 20))
            source.addSubview(reporter)
            window.addSubview(source)
            defer { reporter.removeFromSuperview() }
            let portal = try makeLensPortal(showing: source, frame: CGRect(x: 40, y: 180, width: 120, height: 60))
            window.layer.addSublayer(portal)

            let (_, rects) = try await render(window, with: mirror)
            #expect(rects.contains(window.layer.convert(portal.bounds, from: portal)))
        }

        @Test("A lens portal whose placement isn't affine masks the whole portal when its source has masks")
        func lensPortalWithoutExactMapMasksWholePortal() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let source = UIView(frame: CGRect(x: 20, y: 20, width: 120, height: 60))
            let field = noCaptureView(CGRect(x: 10, y: 10, width: 100, height: 40))
            source.addSubview(field)
            window.addSubview(source)
            let portal = try makeLensPortal(showing: source, frame: CGRect(x: 40, y: 180, width: 120, height: 60))
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 200
            portal.transform = CATransform3DRotate(perspective, 0.4, 0, 1, 0)
            window.layer.addSublayer(portal)

            let (image, rects) = try await render(window, with: mirror)
            #expect(rects.contains(window.layer.convert(portal.bounds, from: portal)))
            #expect(try maskedPixels(image, rects).points(where: Self.isMagenta).isEmpty)
        }

        @Test("Renderers are cached per output scale")
        func renderersAreKeyedByScale() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window, scale: 3)
            #expect(!mirror.needsPrewarm(for: window.bounds.size, scale: 3))
            #expect(mirror.needsPrewarm(for: window.bounds.size, scale: 1.5))
        }

        @Test("An empty window size never waits for a renderer, so a capture can't keep re-waiting for one")
        func emptySizeNeedsNoPrewarm() throws {
            let mirror = try makeMirror()
            #expect(!mirror.needsPrewarm(for: .zero, scale: 1))
            #expect(!mirror.needsPrewarm(for: CGSize(width: 200, height: 0), scale: 1))
            #expect(mirror.needsPrewarm(for: CGSize(width: 200, height: 300), scale: 1))
        }

        @Test("Metal layers render as the placeholder instead of their pixels or nothing", arguments: [1, 0.5] as [CGFloat])
        func metalLayerRendersPlaceholder(scale: CGFloat) async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .red)
            await prewarm(mirror, for: window, scale: scale)

            let metal = MetalView(frame: CGRect(x: 20, y: 40, width: 160, height: 100))
            window.addSubview(metal)

            let pixels = try await Pixels(render(window, with: mirror, scale: scale).0)

            #expect(pixels[Int(10 * scale), Int(10 * scale)] == .red)
            let region = CGRect(x: 20, y: 40, width: 160, height: 100).applying(CGAffineTransform(scaleX: scale, y: scale))
            var grey = 0, transparent = 0
            for y in Int(region.minY) ..< Int(region.maxY) {
                for x in Int(region.minX) ..< Int(region.maxX) {
                    let pixel = pixels[x, y]
                    if pixel.alpha != 255 {
                        transparent += 1
                    }
                    if pixel.red == pixel.green, pixel.green == pixel.blue, pixel.red > 100 {
                        grey += 1
                    }
                }
            }
            #expect(transparent == 0)
            #expect(grey > Int(region.width * region.height) * 8 / 10)
        }

        // MARK: - Lifecycle

        private func makeSut(gpuCapture: Bool = true) throws -> (PostHogSDK, PostHogReplayIntegration, ReplaySnapshots) {
            try makeScreenshotReplaySut { $0.screenshotModeGPUCapture = gpuCapture }
        }

        /// Waits for the capture to give the render slot back, through both turns and the readback.
        private func waitForCaptureToFinish(_ integration: PostHogReplayIntegration) async {
            await waitUntil(timeout: 2) { !integration.isScreenshotRenderInFlightForTesting }
            #expect(!integration.isScreenshotRenderInFlightForTesting)
            await drainReplayQueue()
        }

        /// A window with magenta content inset in a masked field, as text sits in a text field: masks are drawn
        /// with rounded corners, so a fully magenta field would show at the corners.
        private func windowWithContent() -> UIWindow {
            let window = makeWindow()
            let field = noCaptureView(CGRect(x: 10, y: 10, width: 60, height: 50), color: .clear)
            let secret = UIView(frame: field.bounds.insetBy(dx: 5, dy: 5))
            secret.backgroundColor = .magenta
            field.addSubview(secret)
            window.addSubview(field)
            window.layoutIfNeeded()
            return window
        }

        @Test("A first capture waits for its renderer, uploads one screenshot and gives the slot back")
        func captureCompletes() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()

            // No renderer yet: the capture keeps the slot while one is built off-main, then resumes.
            #expect(mirror.needsPrewarm(for: window.bounds.size, scale: PostHogSessionReplayConfig.defaultScreenshotScale))
            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            #expect(integration.isScreenshotRenderInFlightForTesting)

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.count == 1)
        }

        @Test("Replay stopping between the two turns drops the frame and frees the slot")
        func replayStoppedBetweenTurns() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let window = windowWithContent()
            await prewarm(mirror, for: window)

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            sut.stopSessionRecording()

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.isEmpty)
        }

        @Test("The window going away between the two turns drops the frame and frees the slot")
        func windowGoneBetweenTurns() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            await prewarm(mirror, for: makeWindow())

            weak var weakWindow: UIWindow?
            // The pool drains UIKit's autoreleased references; a shown window is retained by the app until hidden.
            let started = autoreleasepool {
                let window = windowWithContent()
                weakWindow = window
                let started = integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut)
                window.isHidden = true
                return started
            }
            #expect(started)
            #expect(weakWindow == nil)

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.isEmpty)
        }

        @Test("The app going to the background between the two turns drops the frame and frees the slot")
        func backgroundedBetweenTurns() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()
            await prewarm(mirror, for: window)

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            mockLifecycle.isInBackground = true

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.isEmpty)
        }

        @Test("With the flag off, a capture takes the default path and never touches the GPU capture")
        func flagOffTakesDefaultPath() async throws {
            let mirror = try makeMirror()
            let (sut, integration, _) = try makeSut(gpuCapture: false)
            defer { sut.close() }
            integration.gpuMirror = mirror
            let window = windowWithContent()

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)
            #expect(mirror.needsPrewarm(for: window.bounds.size, scale: PostHogSessionReplayConfig.defaultScreenshotScale))
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        @Test("GPU capture uploads screenshotScale pixels per point up to native; the default path ignores it", arguments: [
            (gpu: true, scale: nil, width: 200, height: 300), (gpu: true, scale: 1, width: 200, height: 300),
            (gpu: true, scale: 0.5, width: 100, height: 150), (gpu: true, scale: 2, width: 400, height: 600),
            (gpu: true, scale: 5, width: 600, height: 900),
            // Masked default-path frames are redrawn at one pixel per point, as before screenshotScale existed.
            (gpu: false, scale: nil, width: 200, height: 300), (gpu: false, scale: 0.5, width: 200, height: 300),
            (gpu: false, scale: 2, width: 200, height: 300),
        ] as [(gpu: Bool, scale: CGFloat?, width: Int, height: Int)])
        func uploadedScreenshotSize(_ capture: (gpu: Bool, scale: CGFloat?, width: Int, height: Int)) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeScreenshotReplaySut {
                $0.screenshotModeGPUCapture = capture.gpu
                if let scale = capture.scale { $0.screenshotScale = scale }
            }
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()
            try #require(window.screen.scale == 3, "the expected sizes are for a 3x simulator")

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)

            let image = try snapshots.firstScreenshotImage()
            #expect(image.width == capture.width)
            #expect(image.height == capture.height)
            // drawHierarchy has no render server to draw from in this hostless test bundle and leaves the bitmap
            // uninitialized, so only GPU pixels are meaningful here (default-path masking is covered below).
            if capture.gpu {
                #expect(try Pixels(image).points(where: Self.isMagenta).isEmpty)
            }
        }

        @Test("screenshotScale resolves to pixels per point, clamped to the screen's native scale", arguments: [
            (screenshotScale: 1, nativeScale: 3, expected: 1), (screenshotScale: 0.5, nativeScale: 3, expected: 0.5),
            (screenshotScale: 2, nativeScale: 3, expected: 2), (screenshotScale: 5, nativeScale: 3, expected: 3),
            (screenshotScale: 1, nativeScale: 2, expected: 1), (screenshotScale: 2, nativeScale: 2, expected: 2),
            (screenshotScale: 3, nativeScale: 2, expected: 2),
        ] as [(screenshotScale: CGFloat, nativeScale: CGFloat, expected: CGFloat)])
        func screenshotPixelScale(_ scales: (screenshotScale: CGFloat, nativeScale: CGFloat, expected: CGFloat)) {
            let config = PostHogSessionReplayConfig()
            config.screenshotScale = scales.screenshotScale
            #expect(config.screenshotPixelScale(nativeScale: scales.nativeScale) == scales.expected)
        }

        @Test("Shared high-resolution contents are filtered when the mirror downscales them, not point-sampled")
        func downscaledContentsAreFiltered() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window, scale: 0.5)

            // A 1 px black column every 6 px at 3x: thin strokes, as in small glyphs, one per output pixel at 0.5x.
            // Point or bilinear sampling lands between strokes and drops them; filtering keeps 1/6 of each.
            let side = 120
            let stripes = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            stripes.setFillColor(UIColor.white.cgColor)
            stripes.fill(CGRect(x: 0, y: 0, width: side, height: side))
            stripes.setFillColor(UIColor.black.cgColor)
            for x in stride(from: 0, to: side, by: 6) {
                stripes.fill(CGRect(x: x, y: 0, width: 1, height: side))
            }
            let view = UIView(frame: CGRect(x: 20, y: 20, width: 40, height: 40))
            view.layer.contents = stripes.makeImage()
            view.layer.contentsScale = 3
            window.addSubview(view)

            let pixels = try await Pixels(render(window, with: mirror, scale: 0.5).0)
            // The view covers 20 x 20 output pixels; keep clear of its edges.
            let greys = (12 ..< 28).flatMap { y in (12 ..< 28).map { x in Int(pixels[x, y].red) } }
            // 5/6 white: about 212.
            #expect(greys.allSatisfy { (190 ... 235).contains($0) }, "min \(greys.min() ?? -1) max \(greys.max() ?? -1)")
        }

        @Test("screenshotScale defaults to 1, is clamped to at least 0.1, and NaN or infinity reset it to 1", arguments: [
            (input: -CGFloat.greatestFiniteMagnitude, expected: 0.1), (input: -1, expected: 0.1), (input: 0, expected: 0.1),
            (input: 0.05, expected: 0.1), (input: 0.1, expected: 0.1), (input: 0.5, expected: 0.5), (input: 1, expected: 1),
            (input: 2, expected: 2), (input: 5, expected: 5), (input: CGFloat.nan, expected: 1),
            (input: -CGFloat.infinity, expected: 1), (input: CGFloat.infinity, expected: 1),
        ] as [(input: CGFloat, expected: CGFloat)])
        func screenshotScaleIsClamped(_ scale: (input: CGFloat, expected: CGFloat)) {
            let config = PostHogSessionReplayConfig()
            #expect(config.screenshotScale == 1)
            config.screenshotScale = 0.25
            config.screenshotScale = scale.input
            #expect(config.screenshotScale == scale.expected)
        }

        @Test("Mirrored layer trees are freed after each capture")
        func mirroredLayersAreFreed() async throws {
            let mirror = try makeMirror()
            let (sut, integration, _) = try makeScreenshotReplaySut { $0.screenshotModeGPUCapture = true }
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()
            // Nested, as in real screens: only layers below the root's children were kept alive.
            let list = UIView(frame: CGRect(x: 0, y: 70, width: 200, height: 200))
            for row in 0 ..< 40 {
                let label = UILabel(frame: CGRect(x: 10, y: CGFloat(row) * 5, width: 180, height: 5))
                label.text = "Row \(row)"
                list.addSubview(label)
            }
            window.addSubview(list)

            let captures = 30
            for _ in 0 ..< captures {
                #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
                await waitForCaptureToFinish(integration)
            }
            await drainReplayQueue()

            let perCapture = mirror.copiesMadeForTesting / captures
            let live = mirror.copiesForTesting.allObjects.count
            #expect(perCapture > 40)
            #expect(live < perCapture, "\(live) mirror layers alive after \(captures) captures of \(perCapture)")
        }

        // MARK: - Routing

        @Test("GPU capture is used only when its flag is on, and wins over background capture", arguments: [
            (gpu: false, background: false, expected: PostHogReplayIntegration.ScreenshotCapturePath.settled),
            (gpu: false, background: true, expected: .background),
            (gpu: true, background: false, expected: .gpu),
            (gpu: true, background: true, expected: .gpu),
        ])
        func capturePath(_ flags: (gpu: Bool, background: Bool, expected: PostHogReplayIntegration.ScreenshotCapturePath)) {
            let config = PostHogSessionReplayConfig()
            config.screenshotModeGPUCapture = flags.gpu
            config.screenshotModeBackgroundCapture = flags.background
            #expect(PostHogReplayIntegration.screenshotCapturePath(config) == flags.expected)
        }
    }
#endif
