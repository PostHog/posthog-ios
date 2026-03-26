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

#elseif os(macOS)
    import AppKit
    import Foundation

    extension NSImage {
        func toBase64(_ compressionQuality: CGFloat = 0.3) -> String? {
            toWebPBase64(compressionQuality) ?? toJpegBase64(compressionQuality)
        }

        private func toWebPBase64(_ compressionQuality: CGFloat) -> String? {
            webpData(compressionQuality: compressionQuality).map { data in
                "data:image/webp;base64,\(data.base64EncodedString())"
            }
        }

        private func toJpegBase64(_ compressionQuality: CGFloat) -> String? {
            guard let tiffData = tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
            else {
                return nil
            }
            return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        }
    }

    public func imageToBase64(_ image: NSImage, _ compressionQuality: CGFloat = 0.3) -> String? {
        image.toBase64(compressionQuality)
    }

#endif
