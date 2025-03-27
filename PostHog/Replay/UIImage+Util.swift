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
            toWebPBase64(compressionQuality) ?? toJpegBase64(compressionQuality)
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

    public func imageToBase64(_ image: UIImage, _ compressionQuality: CGFloat = 0.3) -> String? {
        image.toBase64(compressionQuality)
    }
#endif
