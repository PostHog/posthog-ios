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
    #if canImport(phlibwebp)
        // SPM package is linked via a lib since mix-code is not yet supported

        // `internal import`: added in Swift 5.9 and it's the "official" feature. Should replace when we switch to swift-tools-version:5.9
        // see: (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md)

        // @_implementationOnly: available since Swift 5.1
        @_implementationOnly import phlibwebp
    #endif
    import UIKit

    extension UIImage {
        /**
         Returns a data object that contains the image in WebP format.

         - Parameters:
         - compressionQuality: desired compression quality [0...1] (0=max/lowest quality, 1=low/high quality)
         - Returns: A data object containing the WebP data, or nil if there’s a problem generating the data.
         */
        func webpData(compressionQuality: CGFloat) -> Data? {
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
    }
#endif
