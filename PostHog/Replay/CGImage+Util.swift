//
//  CGImage+Util.swift
//  PostHog
//
//  Created by Yiannis Josephides on 30/11/2024.
//

#if os(iOS)
    import UIKit

    extension CGImage {
        // This class can maintain many state variables that can impact performance. So for best performance, reuse CIDetector instances instead of creating new ones.
        static var humanFaceDetector: CIDetector = {
            let options = [CIDetectorAccuracy: CIDetectorAccuracyLow]
            return CIDetector(ofType: CIDetectorTypeFace, context: nil, options: options)!
        }()

        private static var ph_human_face_detected_key: UInt8 = 0
        var ph_human_face_detected: Bool? {
            get {
                objc_getAssociatedObject(self, &CGImage.ph_human_face_detected_key) as? Bool
            }

            set {
                objc_setAssociatedObject(
                    self,
                    &CGImage.ph_human_face_detected_key,
                    newValue as Bool?,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
#endif
