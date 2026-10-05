#if os(iOS) && canImport(Metal)
    import IOSurface
    import Metal
    import QuartzCore
    import UIKit

    /// Screenshots a window by rendering a shallow copy of its presentation layer tree, sharing the live layers'
    /// `contents`, with `CARenderer` into a Metal texture: main only walks the tree and encodes the render.
    ///
    /// Not reproduced: content hosted in another render context (`CAPortalLayer`, `CALayerHost`), image-queue
    /// contents such as video, and `CAMetalLayer` pixels, which are drawn as a labelled placeholder.
    final class PostHogGPUMirrorCapture {
        /// One mirrored tree, taken through `freeze`, `encode` and `readback` in that order on main. Each step is
        /// a no-op (or reports failure) out of order or after `release`, and `release` is safe to call more than once,
        /// so every exit of a capture can simply release.
        final class Frame {
            private let target: Target
            /// Pixels per point of the rendered image.
            let scale: CGFloat
            /// The cached wrapper keeps the mirror alive until `release`; this only identifies it.
            private weak var root: CALayer?
            /// Source layers whose whole subtree the mirror left out (hidden, transparent, clipped away or far
            /// off screen). Nothing under them reaches this frame's pixels, so the mask walk can skip them.
            /// Emptied by `freeze`, since the walk runs before it.
            private(set) var culledLayers: Set<ObjectIdentifier>
            private var stage = FrameStage.built

            fileprivate init(target: Target, root: CALayer, culledLayers: Set<ObjectIdentifier>) {
                self.target = target
                scale = target.scale
                self.root = root
                self.culledLayers = culledLayers
            }

            /// Main thread. Commits the mirror so CARenderer sees it; host redraws after this, even in place into shared
            /// contents, don't reach the frame. Call after the mask walk (the commit can move host layers) and in the
            /// same turn as `build`.
            func freeze() {
                guard stage == .built else { return }
                CATransaction.flush()
                culledLayers = []
                stage = .frozen
            }

            /// Main thread, any run-loop turn after `freeze`. Encodes the GPU render without waiting for it; false
            /// when nothing could be encoded.
            func encode() -> Bool {
                guard stage == .frozen, target.render() else { return false }
                stage = .encoded
                return true
            }

            /// Main thread, after `encode`. Calls `completion` on `queue` with the frame's pixels (nil on failure)
            /// once the GPU has finished. Keep the frame unreleased until then.
            func readback(on queue: DispatchQueue, completion: @escaping (CGImage?) -> Void) {
                guard stage == .encoded else {
                    queue.async { completion(nil) }
                    return
                }
                target.readback(on: queue, completion: completion)
            }

            /// Main thread. Detaches the mirror from the cached renderer; the layers are freed off-main.
            func release() {
                guard stage != .released else { return }
                stage = .released
                let wrapper = target.wrapper
                guard wrapper.sublayers?.first === root else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                let detached = wrapper.sublayers
                wrapper.sublayers = nil
                CATransaction.commit()
                PostHogReplayIntegration.dispatchQueue.async { _ = detached }
            }
        }

        private enum FrameStage {
            case built, frozen, encoded, released
        }

        /// A cached renderer and the texture it draws into, for one output size.
        fileprivate final class Target {
            let texture: MTLTexture
            let renderer: CARenderer
            let queue: MTLCommandQueue
            let scale: CGFloat
            let wrapper = CALayer()
            let pixelBounds: CGRect
            /// The texture's layout, BGRA premultiplied.
            private static let bgraBitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

            /// Any thread: the layer changes commit in the calling thread's own transaction.
            init(texture: MTLTexture, queue: MTLCommandQueue, scale: CGFloat) {
                self.texture = texture
                self.scale = scale
                self.queue = queue
                var options: [AnyHashable: Any] = [kCARendererMetalCommandQueue: queue]
                options[kCARendererColorSpace] = CGColorSpace(name: CGColorSpace.sRGB)
                renderer = CARenderer(mtlTexture: texture, options: options)
                pixelBounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                wrapper.anchorPoint = .zero
                wrapper.position = .zero
                wrapper.bounds = pixelBounds
                wrapper.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
                // CARenderer draws drawn and image contents upside down; flipping the wrapper and then the rows on
                // readback brings both back upright.
                wrapper.isGeometryFlipped = true
                CATransaction.commit()
                renderer.layer = wrapper
                renderer.bounds = pixelBounds
            }

            /// Encodes a render of the wrapper's committed tree on `queue`, without waiting for it.
            func render() -> Bool {
                guard clear() else { return false }
                renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
                renderer.addUpdate(pixelBounds)
                renderer.render()
                renderer.endFrame()
                return true
            }

            func readback(on completionQueue: DispatchQueue, completion: @escaping (CGImage?) -> Void) {
                // Command buffers on one queue complete in order, so this empty buffer completes after the render.
                guard let fence = queue.makeCommandBuffer() else {
                    completionQueue.async { completion(nil) }
                    return
                }
                fence.addCompletedHandler { [self] buffer in
                    completionQueue.async {
                        completion(buffer.error == nil ? self.copyPixels() : nil)
                    }
                }
                fence.commit()
            }

            /// Off-main. Renders a small tree with the content kinds UI screens use, so the renderer's pipelines
            /// exist before the first capture, and waits for the GPU. Leaves the wrapper empty.
            func warmUp() {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                wrapper.sublayers = [Self.warmUpTree()]
                CATransaction.commit()
                CATransaction.flush()
                if render(), let fence = queue.makeCommandBuffer() {
                    fence.commit()
                    fence.waitUntilCompleted()
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                wrapper.sublayers = nil
                CATransaction.commit()
                CATransaction.flush()
            }

            private func clear() -> Bool {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
                encoder.endEncoding()
                buffer.commit()
                return true
            }

            private func copyPixels() -> CGImage? {
                let width = texture.width, height = texture.height
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: Self.bgraBitmapInfo),
                    let data = context.data
                else { return nil }
                texture.getBytes(data, bytesPerRow: context.bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                Self.flipRows(data, height: height, bytesPerRow: context.bytesPerRow)
                return context.makeImage()
            }

            private static func flipRows(_ data: UnsafeMutableRawPointer, height: Int, bytesPerRow: Int) {
                let temp = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow, alignment: 16)
                defer { temp.deallocate() }
                for row in 0 ..< height / 2 {
                    let top = data + row * bytesPerRow, bottom = data + (height - 1 - row) * bytesPerRow
                    memcpy(temp, top, bytesPerRow)
                    memcpy(top, bottom, bytesPerRow)
                    memcpy(bottom, temp, bytesPerRow)
                }
            }

            private static func warmUpTree() -> CALayer {
                let root = CALayer()
                root.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
                root.backgroundColor = UIColor.red.cgColor

                let rounded = CALayer()
                rounded.frame = CGRect(x: 8, y: 8, width: 40, height: 40)
                rounded.backgroundColor = UIColor.blue.cgColor
                rounded.cornerRadius = 8
                rounded.borderWidth = 1
                rounded.borderColor = UIColor.black.cgColor
                rounded.masksToBounds = true
                rounded.opacity = 0.9

                let image = CALayer()
                image.frame = CGRect(x: 2, y: 2, width: 20, height: 20)
                image.contents = warmUpImage()
                image.contentsGravity = .resizeAspectFill
                rounded.addSublayer(image)

                let gradient = CAGradientLayer()
                gradient.frame = CGRect(x: 52, y: 8, width: 36, height: 36)
                gradient.colors = [UIColor.white.cgColor, UIColor.green.cgColor]

                let shape = CAShapeLayer()
                shape.frame = CGRect(x: 8, y: 52, width: 36, height: 36)
                shape.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 36, height: 36), transform: nil)
                shape.fillColor = UIColor.yellow.cgColor

                let shadow = CALayer()
                shadow.frame = CGRect(x: 52, y: 52, width: 36, height: 36)
                shadow.backgroundColor = UIColor.white.cgColor
                shadow.shadowOpacity = 0.3
                shadow.shadowRadius = 4
                shadow.transform = CATransform3DMakeRotation(0.1, 0, 0, 1)

                for layer in [rounded, gradient, shape, shadow] {
                    root.addSublayer(layer)
                }
                return root
            }

            private static func warmUpImage() -> CGImage? {
                guard let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bgraBitmapInfo)
                else { return nil }
                context.setFillColor(UIColor.orange.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                return context.makeImage()
            }
        }

        private struct TargetKey: Hashable {
            let width: Int
            let height: Int
            let scale: CGFloat

            init(size: CGSize, scale: CGFloat) {
                width = Int((size.width * scale).rounded(.up))
                height = Int((size.height * scale).rounded(.up))
                self.scale = scale
            }
        }

        /// The CALayer subclass a plain copy is made with.
        private enum LayerKind {
            case plain, gradient, text, shape
        }

        private struct ClassInfo {
            let kind: LayerKind
            let unmirrorable: Bool
            let metal: Bool
            let copiesWithInitLayer: Bool
            let presentationSafe: Bool
        }

        /// State of one `build` walk.
        private struct Walk {
            let scale: CGFloat
            var culled: Set<ObjectIdentifier> = []
        }

        /// Where a layer's sublayers land in the window.
        private enum Space {
            /// `toWindow` maps their positions to window coordinates, and only `visible` of the window (after
            /// clipping ancestors) can still show them.
            case known(toWindow: CGAffineTransform, visible: CGRect)
            /// Not modelled (a 3D, flipped or sublayer transform above, or inside a mask): nothing below is culled.
            case unknown
        }

        /// nil when the device has no Metal; callers keep the `drawHierarchy` path.
        static let shared = PostHogGPUMirrorCapture()

        // Matched by name: these are private Core Animation / UIKit classes with no public symbol to compare against.
        /// Contexts hosting another process's or context's pixels: nothing in-process to share.
        private static let unmirrorableClasses: Set<String> = ["CAPortalLayer", "CALayerHost"]
        /// Backdrop blur only renders through the layer's own class; every other layer is copied into a plain CALayer.
        private static let initLayerClasses: Set<String> = ["UICABackdropLayer", "CABackdropLayer"]
        /// Private contents types safe to share, besides CGImage and IOSurface. Image-queue contents (CAMetalLayer,
        /// video) are excluded: handing them to a second renderer stops the on-screen layer from updating.
        private static let shareablePrivateContentTypes: Set<String> = ["CAIOSurface", "CABackingStore"]
        private static let maxPlaceholders = 8
        /// Slack around the visible rect so antialiased edges of a layer just outside it still render.
        private static let cullMargin: CGFloat = 1
        private static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        private static let defaultAnchor = CGPoint(x: 0.5, y: 0.5)
        private static let nextTurnFallbackDelay: TimeInterval = 0.02

        private let queue: MTLCommandQueue
        private let device: MTLDevice
        // Main thread only.
        private var targets: [TargetKey: Target] = [:]
        private var warming: [TargetKey: [() -> Void]] = [:]
        private var failedKeys: Set<TargetKey> = []
        private var classInfoCache: [ObjectIdentifier: ClassInfo] = [:]
        private var shareableTypeIDs: [CFTypeID: Bool] = [:]
        private var placeholders: [TargetKey: CGImage] = [:]

        /// nil when the device has no Metal. Production code uses `shared`; tests make their own.
        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            self.device = device
            self.queue = queue
        }

        /// Main thread. Runs `block` once, on main, when the run loop next wakes: after this turn's Core Animation commit,
        /// ahead of the next turn's work. The wake-up covers an idle app, the timer a turn that polls instead of waiting.
        static func onNextRunLoopTurn(_ block: @escaping () -> Void) {
            var fired = false
            var cancel: () -> Void = {}
            let runOnce = {
                guard !fired else { return }
                fired = true
                cancel()
                cancel = {}
                block()
            }
            let timer = Timer(timeInterval: nextTurnFallbackDelay, repeats: false) { _ in runOnce() }
            let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, false, 0) { _, _ in
                runOnce()
            }
            cancel = {
                timer.invalidate()
                observer.map { CFRunLoopObserverInvalidate($0) }
            }
            let runLoop = CFRunLoopGetMain()
            RunLoop.main.add(timer, forMode: .common)
            observer.map { CFRunLoopAddObserver(runLoop, $0, .commonModes) }
            CFRunLoopWakeUp(runLoop)
        }

        /// Main thread. Whether a capture at this size would have to create its renderer first. Never for an empty
        /// size, which has no renderer to wait for.
        func needsPrewarm(for size: CGSize, scale: CGFloat) -> Bool {
            let key = TargetKey(size: size, scale: scale)
            return key.width > 0 && key.height > 0 && targets[key] == nil && !failedKeys.contains(key)
        }

        /// Main thread. Creates the renderer for `size` and runs a first render through it off-main, then calls `completion`
        /// on main: both cost tens of ms that would otherwise land on the first capture's main-thread turn.
        func prewarm(size: CGSize, scale: CGFloat, completion: (() -> Void)? = nil) {
            let key = TargetKey(size: size, scale: scale)
            guard key.width > 0, key.height > 0, targets[key] == nil, !failedKeys.contains(key) else {
                completion?()
                return
            }
            if warming[key] != nil {
                if let completion { warming[key]?.append(completion) }
                return
            }
            warming[key] = completion.map { [$0] } ?? []
            DispatchQueue.global(qos: .utility).async { [self] in
                let target = makeTarget(key)
                target?.warmUp()
                DispatchQueue.main.async { [self] in
                    if let target {
                        if targets[key] == nil { install(target, for: key) }
                    } else {
                        // Captures at this size create the renderer on main again, and fall back if that fails too.
                        failedKeys.insert(key)
                    }
                    let completions = warming.removeValue(forKey: key) ?? []
                    completions.forEach { $0() }
                }
            }
        }

        /// Main thread. Mirrors the window's presentation tree and commits it to the renderer's wrapper,
        /// without rendering. The mask walk runs between this and `freeze`, against the same presentation state.
        /// nil when no renderer could be created or nothing of the window renders.
        /// `scale` is the output's pixels per point.
        func build(window: UIWindow, scale: CGFloat) -> Frame? {
            let key = TargetKey(size: window.bounds.size, scale: scale)
            guard key.width > 0, key.height > 0, let target = targets[key] ?? makeAndInstallTarget(key) else { return nil }

            var walk = Walk(scale: scale)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let root = mirrorRoot(window.layer, walk: &walk)
            if target.wrapper.sublayers?.first !== root { target.wrapper.sublayers = root.map { [$0] } }
            CATransaction.commit()
            guard let root else { return nil }
            return Frame(target: target, root: root, culledLayers: walk.culled)
        }

        #if TESTING
            /// Whether a frame's mirror is still attached to a renderer, i.e. built and not yet released.
            var hasAttachedFrameForTesting: Bool {
                targets.values.contains { !($0.wrapper.sublayers ?? []).isEmpty }
            }
        #endif

        // MARK: - Targets

        private func makeAndInstallTarget(_ key: TargetKey) -> Target? {
            guard let target = makeTarget(key) else { return nil }
            install(target, for: key)
            return target
        }

        private func install(_ target: Target, for key: TargetKey) {
            // Rotation alternates between two sizes; anything else is stale.
            if targets.count >= 2 { targets.removeAll() }
            targets[key] = target
        }

        /// Any thread.
        private func makeTarget(_ key: TargetKey) -> Target? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: key.width, height: key.height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget, .shaderRead]
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            return Target(texture: texture, queue: queue, scale: key.scale)
        }

        // MARK: - Mirror

        private func mirrorRoot(_ root: CALayer, walk: inout Walk) -> CALayer? {
            let presentation = root.presentation() ?? root
            // The texture shows the root's frame; culling assumes that frame is the window's bounds.
            let isPlain = presentation.frame.origin == .zero && CATransform3DIsIdentity(presentation.transform)
            // Window coordinates are the root's bounds coordinates, the space mask rects are measured in.
            let space: Space = isPlain ? .known(toWindow: .identity, visible: presentation.bounds) : .unknown
            return mirror(root, parent: .unknown, childSpace: space, walk: &walk)
        }

        /// `parent` is the space the layer's position is expressed in. The root, which isn't placed, passes its
        /// sublayers' space as `childSpace`. Returns nil when nothing of the subtree renders.
        private func mirror(_ source: CALayer, parent: Space, childSpace rootChildSpace: Space? = nil, walk: inout Walk) -> CALayer? {
            let info = classInfo(type(of: source))
            if info.unmirrorable { return nil }
            // Culling reads the model layer unless it's animating: a stale model only costs fidelity (the mask walk
            // skips exactly what the mirror culled), and presentation() allocates a copy per layer. Layers that
            // render are copied from their presentation state, the state the mask rects are measured from.
            let animating = info.presentationSafe && source.animationKeys() != nil
            let geometry = animating ? (source.presentation() ?? source) : source
            if source.isHidden || geometry.isHidden || geometry.opacity == 0 {
                walk.culled.insert(ObjectIdentifier(source))
                return nil
            }

            var ownVisible = true
            var childSpace = rootChildSpace ?? .unknown
            if case let .known(toWindow, visible) = parent {
                guard let placed = place(geometry, info: info, parentToWindow: toWindow, visible: visible) else {
                    walk.culled.insert(ObjectIdentifier(source))
                    return nil
                }
                childSpace = placed.children
                ownVisible = placed.ownVisible
            }

            var children: [CALayer] = []
            for child in source.sublayers ?? [] {
                if let childCopy = mirror(child, parent: childSpace, walk: &walk) {
                    children.append(childCopy)
                }
            }
            if !ownVisible, children.isEmpty {
                walk.culled.insert(ObjectIdentifier(source))
                return nil
            }

            let presentation = (animating || !info.presentationSafe) ? geometry : (source.presentation() ?? source)
            let copy = makeCopy(of: source, presentation: presentation, info: info, walk: &walk)
            if !children.isEmpty { copy.sublayers = children }
            return copy
        }

        private func makeCopy(of source: CALayer, presentation: CALayer, info: ClassInfo, walk: inout Walk) -> CALayer {
            let copy = (info.copiesWithInitLayer ? initLayerCopy(source) : nil) ?? plainCopy(presentation, kind: info.kind)
            copyGeometry(from: presentation, source: source, to: copy)
            copyStyle(from: presentation, to: copy)
            copyContents(from: presentation, source: source, info: info, to: copy)
            copyEffects(from: presentation, source: source, to: copy)

            if info.metal {
                copy.contents = placeholder(size: presentation.bounds.size, scale: walk.scale)
                copy.contentsGravity = .resize
                copy.contentsScale = walk.scale
                copy.contentsRect = Self.unitRect
                copy.contentsCenter = Self.unitRect
            } else if let contents = copy.contents, !isShareable(contents) {
                copy.contents = nil
            }

            if let mask = source.mask {
                // Masks are never culled: a missing mask would show more of the layer, not less.
                copy.mask = mirror(mask, parent: .unknown, walk: &walk)
            }
            return copy
        }

        /// The layer's place in window coordinates. nil when its subtree is left out of the frame: it clips to a
        /// rect outside the visible area, or sits far outside it. Otherwise whether its own bounds reach the
        /// visible area, and the space its sublayers live in. Anything it can't model is kept, not culled.
        private func place(_ layer: CALayer, info: ClassInfo, parentToWindow: CGAffineTransform, visible clip: CGRect) -> (ownVisible: Bool, children: Space)? {
            guard CATransform3DIsAffine(layer.transform) else {
                return (true, .unknown)
            }
            let bounds = layer.bounds
            let anchor = layer.anchorPoint
            let toWindow = CGAffineTransform(translationX: -(bounds.minX + anchor.x * bounds.width), y: -(bounds.minY + anchor.y * bounds.height))
                .concatenating(CATransform3DGetAffineTransform(layer.transform))
                .concatenating(CGAffineTransform(translationX: layer.position.x, y: layer.position.y))
                .concatenating(parentToWindow)
            let frame = bounds.applying(toWindow)
            let visible = clip.insetBy(dx: -Self.cullMargin, dy: -Self.cullMargin)
            var reaches = frame.intersects(visible)
            if !reaches {
                if layer.masksToBounds { return nil }
                // Far cull: a non-clipping layer more than a visible-area's size outside it is left out with its whole
                // subtree, unvisited (off-screen pages and cells; on device it halved the build on large trees). A
                // sublayer positioned back on screen from there is dropped from the pixels, and from the mask walk
                // with it, so a wrong guess costs fidelity, never an unmasked pixel.
                if !frame.intersects(visible.insetBy(dx: -visible.width, dy: -visible.height)) { return nil }
                reaches = ownExtent(layer, info: info).map { $0 != bounds && $0.applying(toWindow).intersects(visible) } ?? true
            }

            // Sublayers sit in bounds coordinates, then sublayerTransform and geometry flipping apply; culling
            // below stops rather than modelling either.
            guard CATransform3DIsIdentity(layer.sublayerTransform), !layer.isGeometryFlipped else {
                return (reaches, .unknown)
            }
            return (reaches, .known(toWindow: toWindow, visible: layer.masksToBounds ? clip.intersection(frame) : clip))
        }

        /// The rect the layer draws its own pixels in (not its sublayers'), in its bounds coordinates, as the
        /// copy this mirror makes of it would draw them; nil when that can't be bounded (shadows, filters,
        /// shape paths, blur). Contents that don't scale to the bounds can spill past them.
        private func ownExtent(_ layer: CALayer, info: ClassInfo) -> CGRect? {
            if info.copiesWithInitLayer || info.kind == .shape || layer.filters != nil { return nil }
            if layer.shadowOpacity > 0, layer.shadowColor != nil { return nil }
            let bounds = layer.bounds
            let gravity = layer.contentsGravity
            guard !info.metal, let contents = layer.contents, gravity != .resize, gravity != .resizeAspect else { return bounds }
            return contentsExtent(layer, contents: contents, gravity: gravity, bounds: bounds)
        }

        /// `ownExtent` for contents drawn with a gravity that doesn't scale them to the bounds.
        private func contentsExtent(_ layer: CALayer, contents: Any, gravity: CALayerContentsGravity, bounds: CGRect) -> CGRect {
            let object = contents as AnyObject
            let typeID = CFGetTypeID(object)
            var size: CGSize
            if typeID == CGImage.typeID {
                let image = object as! CGImage
                size = CGSize(width: image.width, height: image.height)
            } else if typeID == IOSurfaceGetTypeID() {
                let surface = object as! IOSurfaceRef
                size = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
            } else {
                // Backing stores are drawn by the layer itself at its own size.
                return bounds
            }
            let scale = layer.contentsScale > 0 ? layer.contentsScale : 1
            size = CGSize(width: size.width / scale * layer.contentsRect.width, height: size.height / scale * layer.contentsRect.height)
            if gravity == .resizeAspectFill, size.width > 0, size.height > 0 {
                let fill = max(bounds.width / size.width, bounds.height / size.height)
                size = CGSize(width: size.width * fill, height: size.height * fill)
            }
            return bounds.insetBy(dx: -max(0, size.width - bounds.width), dy: -max(0, size.height - bounds.height))
        }

        // The copy helpers set only what differs from a fresh layer's defaults: each set is a transaction write,
        // and most layers in a UI tree are plain, unrounded, unshadowed rectangles.

        private func copyGeometry(from presentation: CALayer, source: CALayer, to copy: CALayer) {
            copy.bounds = presentation.bounds
            copy.position = presentation.position
            if presentation.anchorPoint != Self.defaultAnchor { copy.anchorPoint = presentation.anchorPoint }
            if presentation.zPosition != 0 { copy.zPosition = presentation.zPosition }
            if !CATransform3DIsIdentity(presentation.transform) { copy.transform = presentation.transform }
            if !CATransform3DIsIdentity(presentation.sublayerTransform) { copy.sublayerTransform = presentation.sublayerTransform }
            if source.masksToBounds { copy.masksToBounds = true }
            if source.isGeometryFlipped { copy.isGeometryFlipped = true }
        }

        private func copyStyle(from presentation: CALayer, to copy: CALayer) {
            if presentation.opacity != 1 { copy.opacity = presentation.opacity }
            if let color = presentation.backgroundColor { copy.backgroundColor = color }
            if presentation.cornerRadius != 0 {
                copy.cornerRadius = presentation.cornerRadius
                copy.cornerCurve = presentation.cornerCurve
                copy.maskedCorners = presentation.maskedCorners
            }
            if presentation.borderWidth != 0 {
                copy.borderWidth = presentation.borderWidth
                copy.borderColor = presentation.borderColor
            }
            if presentation.shadowOpacity != 0 {
                copy.shadowColor = presentation.shadowColor
                copy.shadowOpacity = presentation.shadowOpacity
                copy.shadowOffset = presentation.shadowOffset
                copy.shadowRadius = presentation.shadowRadius
                copy.shadowPath = presentation.shadowPath
            }
        }

        private func copyContents(from presentation: CALayer, source: CALayer, info _: ClassInfo, to copy: CALayer) {
            // Also sets the rasterization scale of text and shape layers, which have no contents.
            if source.contentsScale != 1 { copy.contentsScale = source.contentsScale }
            guard let contents = presentation.contents ?? source.contents else { return }
            copy.contents = contents
            if source.contentsGravity != .resize { copy.contentsGravity = source.contentsGravity }
            if presentation.contentsRect != Self.unitRect { copy.contentsRect = presentation.contentsRect }
            if source.contentsCenter != Self.unitRect { copy.contentsCenter = source.contentsCenter }
            if source.minificationFilter != .linear { copy.minificationFilter = source.minificationFilter }
            if source.magnificationFilter != .linear { copy.magnificationFilter = source.magnificationFilter }
        }

        private func copyEffects(from presentation: CALayer, source: CALayer, to copy: CALayer) {
            if source.allowsEdgeAntialiasing { copy.allowsEdgeAntialiasing = true }
            if !source.allowsGroupOpacity { copy.allowsGroupOpacity = false }
            if let filters = presentation.filters { copy.filters = filters }
            if let filters = presentation.backgroundFilters { copy.backgroundFilters = filters }
            if let filter = presentation.compositingFilter { copy.compositingFilter = filter }
        }

        private func plainCopy(_ presentation: CALayer, kind: LayerKind) -> CALayer {
            switch kind {
            case .gradient:
                let gradient = presentation as! CAGradientLayer
                let copy = CAGradientLayer()
                copy.colors = gradient.colors
                copy.locations = gradient.locations
                copy.startPoint = gradient.startPoint
                copy.endPoint = gradient.endPoint
                copy.type = gradient.type
                return copy
            case .text:
                let text = presentation as! CATextLayer
                let copy = CATextLayer()
                copy.string = text.string
                copy.font = text.font
                copy.fontSize = text.fontSize
                copy.foregroundColor = text.foregroundColor
                copy.alignmentMode = text.alignmentMode
                copy.isWrapped = text.isWrapped
                copy.truncationMode = text.truncationMode
                return copy
            case .shape:
                let shape = presentation as! CAShapeLayer
                let copy = CAShapeLayer()
                copy.path = shape.path
                copy.fillColor = shape.fillColor
                copy.strokeColor = shape.strokeColor
                copy.lineWidth = shape.lineWidth
                copy.fillRule = shape.fillRule
                copy.lineCap = shape.lineCap
                copy.lineJoin = shape.lineJoin
                copy.lineDashPattern = shape.lineDashPattern
                copy.strokeStart = shape.strokeStart
                copy.strokeEnd = shape.strokeEnd
                return copy
            case .plain:
                return CALayer()
            }
        }

        /// `[cls alloc]` + `initWithLayer:` through the runtime: Swift can't call a non-required initializer on a
        /// metatype. alloc's +1 is consumed by init; init's result is returned retained.
        private func initLayerCopy(_ source: CALayer) -> CALayer? {
            let cls: AnyClass = type(of: source)
            guard let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                  let copy = (allocated as AnyObject).perform(NSSelectorFromString("initWithLayer:"), with: source)?.takeRetainedValue() as? CALayer,
                  type(of: copy) == cls, copy.superlayer == nil, (copy.sublayers ?? []).isEmpty, copy.mask == nil
            else { return nil }
            copy.delegate = nil
            return copy
        }

        private func classInfo(_ cls: AnyClass) -> ClassInfo {
            let key = ObjectIdentifier(cls)
            if let cached = classInfoCache[key] { return cached }
            var chain: [String] = []
            var current: AnyClass? = cls
            while let next = current {
                chain.append(NSStringFromClass(next))
                current = class_getSuperclass(next)
            }
            let kind: LayerKind
            if chain.contains("CAGradientLayer") {
                kind = .gradient
            } else if chain.contains("CATextLayer") {
                kind = .text
            } else if chain.contains("CAShapeLayer") {
                kind = .shape
            } else {
                kind = .plain
            }
            let info = ClassInfo(kind: kind,
                                 unmirrorable: chain.contains { Self.unmirrorableClasses.contains($0) },
                                 metal: chain.contains("CAMetalLayer"),
                                 copiesWithInitLayer: chain.contains { Self.initLayerClasses.contains($0) },
                                 presentationSafe: Self.isPresentationSafe(cls))
            classInfoCache[key] = info
            return info
        }

        /// `presentation()` instantiates the layer's class through `initWithLayer:`; a Swift subclass that doesn't
        /// override `init(layer:)` traps there. CALayer's own implementation, and any that lives in a system image
        /// (found with `dladdr`, since the app's own subclasses are the ones that can trap), are trusted.
        private static func isPresentationSafe(_ cls: AnyClass) -> Bool {
            let selector = NSSelectorFromString("initWithLayer:")
            let implementation = class_getMethodImplementation(cls, selector)
            if implementation == class_getMethodImplementation(CALayer.self, selector) { return true }
            var info = Dl_info()
            guard dladdr(unsafeBitCast(implementation, to: UnsafeRawPointer.self), &info) != 0, let name = info.dli_fname else { return false }
            let path = String(cString: name)
            return path.contains("/System/Library/") || path.contains("/usr/lib/")
        }

        private func isShareable(_ contents: Any) -> Bool {
            let typeID = CFGetTypeID(contents as AnyObject)
            if let cached = shareableTypeIDs[typeID] { return cached }
            let shareable = typeID == CGImage.typeID || typeID == IOSurfaceGetTypeID()
                || Self.shareablePrivateContentTypes.contains((CFCopyTypeIDDescription(typeID) as String?) ?? "")
            shareableTypeIDs[typeID] = shareable
            return shareable
        }

        // MARK: - Metal placeholder

        /// Grey with stripes and a label, so it isn't mistaken for a privacy mask.
        private func placeholder(size: CGSize, scale: CGFloat) -> CGImage? {
            let key = TargetKey(size: size, scale: scale)
            guard key.width > 0, key.height > 0 else { return nil }
            if let cached = placeholders[key] { return cached }
            let image = PostHogGraphicsImageRenderer(size: size, scale: scale).image { context in
                let bounds = CGRect(origin: .zero, size: size)
                UIColor(white: 0.62, alpha: 1).setFill()
                context.fill(bounds)

                context.saveGState()
                context.clip(to: bounds)
                context.setStrokeColor(UIColor(white: 0.52, alpha: 1).cgColor)
                context.setLineWidth(6)
                for offset in stride(from: -size.height, to: size.width, by: 18) {
                    context.move(to: CGPoint(x: offset, y: size.height))
                    context.addLine(to: CGPoint(x: offset + size.height, y: 0))
                }
                context.strokePath()
                context.restoreGState()

                let text = "Metal content" as NSString
                let fontSize = min(17, max(8, min(size.width / 9, size.height / 3)))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: UIColor(white: 0.15, alpha: 1),
                ]
                let textSize = text.size(withAttributes: attributes)
                let label = CGRect(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2,
                                   width: textSize.width, height: textSize.height)
                UIColor(white: 0.85, alpha: 1).setFill()
                UIBezierPath(roundedRect: label.insetBy(dx: -8, dy: -4), cornerRadius: 6).fill()
                text.draw(in: label, withAttributes: attributes)
            }?.cgImage
            if placeholders.count >= Self.maxPlaceholders { placeholders.removeAll() }
            placeholders[key] = image
            return image
        }
    }
#endif
