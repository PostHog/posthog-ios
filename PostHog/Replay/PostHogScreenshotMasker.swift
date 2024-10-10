//
//  PostHogScreenshotMasker.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 23.09.24.
//

#if os(iOS) && canImport(SwiftUI)
    import Foundation
    import SwiftUI

    class PostHogScreenshotMasker {
        public static let shared = PostHogScreenshotMasker()

        private var maskedViews: [UIView] = []

        // Private initializer to prevent multiple instances
        private init() {}

        func addView(_ view: UIView) {
            if !maskedViews.contains(view) {
                maskedViews.append(view)
            }
        }

        func removeView(_ view: UIView) {
            maskedViews.removeAll { $0 == view }
        }

        func getAllMaskedViews() -> [UIView] {
            maskedViews
        }

        func clearMaskedViews() {
            maskedViews.removeAll()
        }
    }

#endif
