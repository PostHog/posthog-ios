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
            let jpegData = jpegData(compressionQuality: compressionQuality)
            let base64 = jpegData?.base64EncodedString()

            if let base64 = base64 {
                return "data:image/jpeg;base64,\(base64)"
            }

            return nil
        }
    }

    public func imageToBase64(_ image: UIImage, _ compressionQuality: CGFloat = 0.3) -> String? {
        image.toBase64(compressionQuality)
    }
#endif
