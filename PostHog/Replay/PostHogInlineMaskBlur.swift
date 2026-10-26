#if os(iOS) && canImport(Metal)
    import Accelerate
    import QuartzCore

    extension PostHogInlineMask {
        typealias RegionBlur = (_ region: vImage_Buffer) -> Bool

        #if TESTING
            /// Time the last readback spent blurring masked images. Written on the readback queue.
            static var lastBlurMillisecondsForTesting: Double = 0
        #endif

        /// Blurs the region in place to about `blurCellsAcross` cells across its long side, using only its own pixels so
        /// nothing smears in or out: downscale (averaging), box-blur, upscale. False when vImage fails.
        static func blurInPlace(_ region: vImage_Buffer) -> Bool {
            let width = Int(region.width), height = Int(region.height)
            guard width > 0, height > 0 else { return true }
            let longSide = CGFloat(max(width, height)), smallLongSide = blurCellsAcross * 4
            let factor = min(1, smallLongSide / longSide)
            let smallWidth = max(1, Int((CGFloat(width) * factor).rounded())), smallHeight = max(1, Int((CGFloat(height) * factor).rounded()))
            var small = vImage_Buffer(), blurred = vImage_Buffer()
            guard vImageBuffer_Init(&small, vImagePixelCount(smallHeight), vImagePixelCount(smallWidth), 32, vImage_Flags(kvImageNoFlags)) == kvImageNoError
            else { return false }
            defer { free(small.data) }
            guard vImageBuffer_Init(&blurred, small.height, small.width, 32, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return false }
            defer { free(blurred.data) }
            var original = region
            guard vImageScale_ARGB8888(&original, &small, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else { return false }
            // Three box passes a quarter of the long side wide: close to a gaussian with a sixth of it as its radius.
            let kernel = Int(max(3, (CGFloat(max(smallWidth, smallHeight)) / 4).rounded()))
            let kernelWidth = UInt32(min(kernel, smallWidth) | 1), kernelHeight = UInt32(min(kernel, smallHeight) | 1)
            var source = small, destination = blurred
            for _ in 0 ..< 3 {
                guard vImageBoxConvolve_ARGB8888(&source, &destination, nil, 0, 0, kernelHeight, kernelWidth, nil,
                                                 vImage_Flags(kvImageEdgeExtend)) == kvImageNoError
                else { return false }
                swap(&source, &destination)
            }
            return vImageScale_ARGB8888(&source, &original, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }

        /// How far, in points, past its bounds a backdrop may sample and spread what's behind it.
        static let backdropReach: CGFloat = 40

        /// Blurs each rect (pixels) of a top-down BGRA bitmap in place, or fills it black when its blur fails, so its
        /// unblurred pixels never leave the bitmap.
        static func blurRegions(_ rects: [CGRect], in data: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int,
                                blur: RegionBlur = blurInPlace)
        {
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            for rect in rects {
                let pixels = rect.integral.intersection(bounds)
                guard !pixels.isEmpty else { continue }
                let region = vImage_Buffer(data: data + Int(pixels.minY) * bytesPerRow + Int(pixels.minX) * 4, height: vImagePixelCount(pixels.height),
                                           width: vImagePixelCount(pixels.width), rowBytes: bytesPerRow)
                if !blur(region) { fillBlack(region) }
            }
        }

        private static func fillBlack(_ region: vImage_Buffer) {
            for row in 0 ..< Int(region.height) {
                let pixels = (region.data + row * region.rowBytes).assumingMemoryBound(to: UInt32.self)
                // BGRA little-endian: opaque black is alpha alone.
                for column in 0 ..< Int(region.width) {
                    pixels[column] = 0xFF00_0000
                }
            }
        }

        // MARK: - Self-check

        static let blurCheckWidth = 48
        static let blurCheckHeight = 32
        private static let blurCheckCell = 2
        /// Largest step between neighbouring pixels, out of 255, a blurred checkerboard may keep.
        static let blurCheckMaxStep = 12

        /// A fine black and white checkerboard, `blurCheckWidth` by `blurCheckHeight` BGRA pixels: the detail an image
        /// blur has to remove.
        static func blurCheckPattern() -> [UInt32] {
            var pixels = [UInt32](repeating: 0xFF00_0000, count: blurCheckWidth * blurCheckHeight)
            for row in 0 ..< blurCheckHeight {
                for column in 0 ..< blurCheckWidth where (row / blurCheckCell + column / blurCheckCell) % 2 == 0 {
                    pixels[row * blurCheckWidth + column] = 0xFFFF_FFFF
                }
            }
            return pixels
        }

        /// Any thread. Blurs a fine checkerboard through `blur` and reports whether its detail is gone; false when it
        /// isn't or the blur couldn't run.
        static func checkImageBlur(applying blur: RegionBlur = blurInPlace) -> Bool {
            var pixels = blurCheckPattern()
            let width = blurCheckWidth, height = blurCheckHeight, bytesPerRow = width * 4
            return pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let data = buffer.baseAddress else { return false }
                let region = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
                guard blur(region) else { return false }
                let bytes = UnsafePointer(data.assumingMemoryBound(to: UInt8.self))
                return maxNeighbourStep(bytes, width: width, height: height, bytesPerRow: bytesPerRow) <= blurCheckMaxStep
            }
        }

        /// The largest difference between horizontally or vertically adjacent pixels in any colour channel. A 2-px
        /// margin is left out, where edge handling rather than the blur decides the values.
        static func maxNeighbourStep(_ bytes: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> Int {
            let margin = 2
            var step = 0
            for row in margin ..< height - margin - 1 {
                for column in margin ..< width - margin - 1 {
                    let index = row * bytesPerRow + column * 4
                    for channel in 0 ..< 3 {
                        let value = Int(bytes[index + channel])
                        step = max(step, abs(value - Int(bytes[index + 4 + channel])), abs(value - Int(bytes[index + bytesPerRow + channel])))
                    }
                }
            }
            return step
        }
    }
#endif
