//
//  UIImage+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.11.24.
//

#if os(iOS)
    import Foundation
    import UIKit

    extension UIImage {
        func toBase64(_ compressionQuality: CGFloat = 0.3) -> String? {
            autoreleasepool {
                toWebPBase64(compressionQuality) ?? toJpegBase64(compressionQuality)
            }
        }

        private func toWebPBase64(_ compressionQuality: CGFloat) -> String? {
            webpData(compressionQuality: compressionQuality).map { data in
                "data:image/webp;base64,\(data.base64EncodedString())"
            }
        }

        private func toJpegBase64(_ compressionQuality: CGFloat) -> String? {
            jpegData(compressionQuality: compressionQuality).map { data in
                "data:image/jpeg;base64,\(data.base64EncodedString())"
            }
        }
    }

    /// Encodes an image as a data URL string for session replay snapshots.
    ///
    /// The SDK tries WebP first and falls back to JPEG.
    ///
    /// - Parameters:
    ///   - image: Image to encode.
    ///   - compressionQuality: Compression quality from `0.0` to `1.0`. Defaults to `0.3`.
    /// - Returns: A `data:image/...;base64` string, or `nil` if encoding fails.
    public func imageToBase64(_ image: UIImage, _ compressionQuality: CGFloat = 0.3) -> String? {
        image.toBase64(compressionQuality)
    }
#endif
