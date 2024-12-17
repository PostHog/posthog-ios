//
//  UIImage+WebP.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/12/2024.
//
// Adapted from: https://github.com/SDWebImage/SDWebImageWebPCoder/blob/master/SDWebImageWebPCoder/Classes/SDImageWebPCoder.m

#if os(iOS)
    import Accelerate
    import CoreGraphics
    import Foundation
    #if canImport(libwebp)
        // SPM package is linked via a lib since mix-code is not yet supported
        import libwebp
    #endif
    import UIKit

    extension UIImage {
        /**
         Returns a data object that contains the image in WebP format.

         - Parameters:
         - compressionQuality: desired compression quality [0...1] (0=max/lowest quality, 1=low/high quality)
         - options: list of [WebPOption]
         - Returns: A data object containing the WebP data, or nil if there’s a problem generating the data.
         */
        func webpData(compressionQuality: CGFloat, options: [WebPOption] = []) -> Data? {
            // Early exit if image is missing
            guard let cgImage = cgImage else {
                return nil
            }

            // validate dimensions
            let width = Int(cgImage.width)
            let height = Int(cgImage.height)

            guard width > 0, width <= WEBP_MAX_DIMENSION, height > 0, height <= WEBP_MAX_DIMENSION else {
                return nil
            }

            let bitmapInfo = cgImage.bitmapInfo
            let alphaInfo = CGImageAlphaInfo(rawValue: bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)

            // Prepare destination format

            let hasAlpha = !(
                alphaInfo == CGImageAlphaInfo.none ||
                    alphaInfo == CGImageAlphaInfo.noneSkipFirst ||
                    alphaInfo == CGImageAlphaInfo.noneSkipLast
            )

            // try to use image color space if ~rgb
            let colorSpace: CGColorSpace = cgImage.colorSpace?.model == .rgb
                ? cgImage.colorSpace! // safe from previous check
                : CGColorSpace(name: CGColorSpace.linearSRGB)!
            let renderingIntent = cgImage.renderingIntent

            guard let destFormat = vImage_CGImageFormat(
                bitsPerComponent: 8,
                bitsPerPixel: hasAlpha ? 32 : 24, // RGB888/RGBA8888
                colorSpace: colorSpace,
                bitmapInfo: hasAlpha
                    ? CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrderDefault.rawValue)
                    : CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrderDefault.rawValue),
                renderingIntent: renderingIntent
            ) else {
                return nil
            }

            guard let dest = try? vImage_Buffer(cgImage: cgImage, format: destFormat, flags: .noFlags) else {
                hedgeLog("Error initializing WebP image buffer")
                return nil
            }
            defer { dest.data?.deallocate() }

            guard let rgba = dest.data else { // byte array
                hedgeLog("Could not get rgba byte array from destination format")
                return nil
            }
            let bytesPerRow = dest.rowBytes

            let quality = Float(compressionQuality * 100) // WebP quality is 0-100

            var config = WebPConfig()
            var picture = WebPPicture()
            var writer = WebPMemoryWriter()

            // get present...
            guard WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, quality) != 0, WebPPictureInit(&picture) != 0 else {
                hedgeLog("Error initializing WebPPicture")
                return nil
            }
            // ...and set options
            setWebPOptions(config: &config, options: options)

            withUnsafeMutablePointer(to: &writer) { writerPointer in
                picture.use_argb = 1 // Lossy encoding uses YUV for internal bitstream
                picture.width = Int32(width)
                picture.height = Int32(height)
                picture.writer = WebPMemoryWrite
                picture.custom_ptr = UnsafeMutableRawPointer(writerPointer)
            }

            WebPMemoryWriterInit(&writer)

            defer {
                WebPMemoryWriterClear(&writer)
                WebPPictureFree(&picture)
            }

            let result: Int32
            if hasAlpha {
                // RGBA8888 - 4 channels
                result = WebPPictureImportRGBA(&picture, rgba.bindMemory(to: UInt8.self, capacity: 4), Int32(bytesPerRow))
            } else {
                // RGB888 - 3 channels
                result = WebPPictureImportRGB(&picture, rgba.bindMemory(to: UInt8.self, capacity: 3), Int32(bytesPerRow))
            }

            if result == 0 {
                hedgeLog("Could not read WebPPicture")
                return nil
            }

            if WebPEncode(&config, &picture) == 0 {
                hedgeLog("Could not encode WebP image")
                return nil
            }

            let webpData = Data(bytes: writer.mem, count: writer.size)

            return webpData
        }

        // swiftlint:disable:next cyclomatic_complexity
        private func setWebPOptions(
            config: UnsafeMutablePointer<WebPConfig>,
            options: [WebPOption]
        ) {
            for option in options {
                switch option {
                case let .targetSize(value):
                    config.pointee.target_size = value
                case let .emulateJPEGSize(value):
                    config.pointee.emulate_jpeg_size = value ? 1 : 0
                case let .nearLossless(value):
                    config.pointee.near_lossless = value
                case let .lossless(value):
                    config.pointee.lossless = value ? 1 : 0
                case let .exact(value):
                    config.pointee.exact = value ? 1 : 0
                case let .method(value):
                    config.pointee.method = value
                case let .targetPSNR(value):
                    config.pointee.target_PSNR = Float(value)
                case let .segments(value):
                    config.pointee.segments = value
                case let .snsStrength(value):
                    config.pointee.sns_strength = value
                case let .filterStrength(value):
                    config.pointee.filter_strength = value
                case let .filterSharpness(value):
                    config.pointee.filter_sharpness = value
                case let .filterType(value):
                    config.pointee.filter_type = value
                case let .autofilter(value):
                    config.pointee.autofilter = value ? 1 : 0
                case let .alphaCompression(value):
                    config.pointee.alpha_compression = value
                case let .alphaFiltering(value):
                    config.pointee.alpha_filtering = value
                case let .alphaQuality(value):
                    config.pointee.alpha_quality = value
                case let .passes(value):
                    config.pointee.pass = value
                case let .showCompressed(value):
                    config.pointee.show_compressed = value ? 1 : 0
                case let .preprocessing(value):
                    config.pointee.preprocessing = value
                case let .partitions(value):
                    config.pointee.partitions = value
                case let .partitionLimit(value):
                    config.pointee.partition_limit = value
                case let .threadLevel(value):
                    config.pointee.thread_level = value ? 1 : 0
                case let .lowMemory(value):
                    config.pointee.low_memory = value ? 1 : 0
                case let .useDeltaPalette(value):
                    config.pointee.use_delta_palette = value ? 1 : 0
                case let .useSharpYUV(value):
                    config.pointee.use_sharp_yuv = value ? 1 : 0
                }
            }
        }
    }

    enum WebPOption {
        /// If non-zero, set the desired target size in bytes. Takes precedence over the 'compression' parameter.
        case targetSize(Int32)

        /// If true, compression parameters will be remapped to better match the expected output size from JPEG compression. Generally, the output size will be similar but the degradation will be lower.
        case emulateJPEGSize(Bool)

        /// Near lossless encoding [0 = max loss .. 100 = off (default)].
        case nearLossless(Int32)

        /// Lossless encoding (0=lossy(default), 1=lossless).
        case lossless(Bool)

        /// If non-zero, preserve the exact RGB values under transparent area. Otherwise, discard this invisible RGB information for better compression. The default value is 0.
        case exact(Bool)

        /// Quality/speed trade-off (0=fast, 6=slower-better).
        case method(Int32)

        /// If non-zero, specifies the minimal distortion to try to achieve. Takes precedence over target_size.
        case targetPSNR(CGFloat)

        /// Maximum number of segments to use, in [1..4].
        case segments(Int32)

        /// Spatial Noise Shaping. 0=off, 100=maximum. Default is 50.
        case snsStrength(Int32)

        /// Range: [0 = off .. 100 = strongest]. Default is 60.
        case filterStrength(Int32)

        /// Range: [0 = off .. 7 = least sharp]. Default is 0.
        case filterSharpness(Int32)

        /// Filtering type: 0 = simple, 1 = strong (only used if filter_strength > 0 or autofilter > 0). Default is 1.
        case filterType(Int32)

        /// Auto adjust filter's strength [0 = off, 1 = on]. Default is 0.
        case autofilter(Bool)

        /// Algorithm for encoding the alpha plane (0 = none, 1 = compressed with WebP lossless). Default is 1.
        case alphaCompression(Int32)

        /// Predictive filtering method for alpha plane. 0: none, 1: fast, 2: best. Default is 1.
        case alphaFiltering(Int32)

        /// Between 0 (smallest size) and 100 (lossless). Default is 100.
        case alphaQuality(Int32)

        /// Number of entropy-analysis passes (in [1..10]). Default is 1.
        case passes(Int32)

        /// If true, export the compressed picture back. In-loop filtering is not applied.
        case showCompressed(Bool)

        /// Preprocessing filter (0=none, 1=segment-smooth, 2=pseudo-random dithering). Default is 0.
        case preprocessing(Int32)

        /// Log2(number of token partitions) in [0..3]. Default is set to 0 for easier progressive decoding.
        case partitions(Int32)

        /// Quality degradation allowed to fit the 512k limit on prediction modes coding (0: no degradation, 100: maximum possible degradation). Default is 0.
        case partitionLimit(Int32)

        /// If non-zero, try and use multi-threaded encoding.
        case threadLevel(Bool)

        /// If set, reduce memory usage (but increase CPU use).
        case lowMemory(Bool)

        /// Reserved for future lossless feature.
        case useDeltaPalette(Bool)

        /// If needed, use sharp (and slow) RGB->YUV conversion.
        case useSharpYUV(Bool)
    }
#endif
