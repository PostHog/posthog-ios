#if os(iOS) && canImport(Metal)
    import Metal
    import QuartzCore
    import UIKit

    extension PostHogGPUMirrorCapture {
        /// A cached renderer and the texture it draws into, for one output size.
        final class Target {
            let texture: MTLTexture
            let renderer: CARenderer
            let queue: MTLCommandQueue
            let scale: CGFloat
            let wrapper = CALayer()
            let pixelBounds: CGRect
            /// The clear the latest `render` encoded: the only part of a render whose result can be checked, since
            /// CARenderer doesn't expose its own command buffer.
            private var lastClear: MTLCommandBuffer?
            /// The texture's layout, BGRA premultiplied.
            static let bgraBitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

            /// Any thread: the layer changes commit in the calling thread's own transaction.
            private init(texture: MTLTexture, queue: MTLCommandQueue, scale: CGFloat) {
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
                guard let clear = clear() else { return false }
                lastClear = clear
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
                let clear = lastClear
                fence.addCompletedHandler { [self] buffer in
                    let failed = buffer.error != nil || clear?.status != .completed
                    completionQueue.async {
                        completion(failed ? nil : self.copyPixels())
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

            private func clear() -> MTLCommandBuffer? {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
                encoder.endEncoding()
                buffer.commit()
                return buffer
            }

            private func copyPixels() -> CGImage? {
                let width = texture.width, height = texture.height
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: Self.bgraBitmapInfo),
                    let data = context.data
                else { return nil }
                texture.getBytes(data, bytesPerRow: context.bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                // A window paints at least its background, so a frame with every pixel transparent is a render that
                // didn't happen. The scan stops at the first painted pixel, which is usually the first one.
                guard !Self.isBlank(data, width: width, height: height, bytesPerRow: context.bytesPerRow) else { return nil }
                Self.flipRows(data, height: height, bytesPerRow: context.bytesPerRow)
                return context.makeImage()
            }

            private static func isBlank(_ data: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
                for row in 0 ..< height {
                    let pixels = (data + row * bytesPerRow).assumingMemoryBound(to: UInt32.self)
                    // BGRA little-endian: alpha is the top byte.
                    for column in 0 ..< width where pixels[column] & 0xFF00_0000 != 0 {
                        return false
                    }
                }
                return true
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

            /// Any thread.
            static func make(_ key: TargetKey, device: MTLDevice, queue: MTLCommandQueue) -> Target? {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: key.width, height: key.height, mipmapped: false)
                descriptor.storageMode = .shared
                descriptor.usage = [.renderTarget, .shaderRead]
                guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
                return Target(texture: texture, queue: queue, scale: key.scale)
            }

            /// Off-main. Renders `layer` alone, waits for the GPU and returns the pixels. Leaves the wrapper empty.
            private func renderSynchronously(_ layer: CALayer) -> CGImage? {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                wrapper.sublayers = [layer]
                CATransaction.commit()
                CATransaction.flush()
                var image: CGImage?
                if render(), let fence = queue.makeCommandBuffer() {
                    fence.commit()
                    fence.waitUntilCompleted()
                    image = fence.error == nil ? copyPixels() : nil
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                wrapper.sublayers = nil
                CATransaction.commit()
                CATransaction.flush()
                return image
            }

            // MARK: Image blur self-check

            /// A fine black and white checkerboard, the detail an image blur has to remove.
            private static let blurCheckSize = CGSize(width: 48, height: 32)
            private static let blurCheckCell = 2
            /// Largest step between neighbouring pixels, out of 255, a blurred checkerboard may keep.
            private static let blurCheckMaxStep = 12

            /// Off-main. Renders a fine checkerboard through `blur` on its own small renderer and reports whether the
            /// detail is gone; false when `CARenderer` left it or nothing could be rendered.
            static func checkImageBlur(device: MTLDevice, queue: MTLCommandQueue, applying blur: (CALayer) -> Bool) -> Bool {
                guard let target = make(TargetKey(size: blurCheckSize, scale: 1), device: device, queue: queue), let pattern = checkerboard()
                else { return false }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                let layer = CALayer()
                layer.anchorPoint = .zero
                layer.bounds = CGRect(origin: .zero, size: blurCheckSize)
                layer.contents = pattern
                let applied = blur(layer)
                CATransaction.commit()
                guard applied, let image = target.renderSynchronously(layer) else { return false }
                return maxNeighbourStep(image).map { $0 <= blurCheckMaxStep } ?? false
            }

            private static func checkerboard() -> CGImage? {
                let width = Int(blurCheckSize.width), height = Int(blurCheckSize.height), cell = blurCheckCell
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return nil }
                context.setFillColor(UIColor.black.cgColor)
                context.fill(CGRect(origin: .zero, size: blurCheckSize))
                context.setFillColor(UIColor.white.cgColor)
                for row in stride(from: 0, to: height, by: cell) {
                    for column in stride(from: (row / cell % 2) * cell, to: width, by: cell * 2) {
                        context.fill(CGRect(x: column, y: row, width: cell, height: cell))
                    }
                }
                return context.makeImage()
            }

            /// The largest difference between horizontally or vertically adjacent pixels in any channel, away from the
            /// edges; nil when the image couldn't be read.
            private static func maxNeighbourStep(_ image: CGImage) -> Int? {
                let width = image.width, height = image.height, margin = 2
                guard width > 2 * margin + 1, height > 2 * margin + 1 else { return nil }
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
                    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }
                guard drawn else { return nil }
                var step = 0
                for row in margin ..< height - margin - 1 {
                    for column in margin ..< width - margin - 1 {
                        let index = (row * width + column) * 4
                        for channel in 0 ..< 3 {
                            let value = Int(bytes[index + channel])
                            step = max(step, abs(value - Int(bytes[index + 4 + channel])), abs(value - Int(bytes[index + width * 4 + channel])))
                        }
                    }
                }
                return step
            }
        }

        struct TargetKey: Hashable {
            let width: Int
            let height: Int
            let scale: CGFloat

            init(size: CGSize, scale: CGFloat) {
                width = Int((size.width * scale).rounded(.up))
                height = Int((size.height * scale).rounded(.up))
                self.scale = scale
            }
        }
    }
#endif
