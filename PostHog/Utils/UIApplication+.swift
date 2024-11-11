//
//  UIApplication+.swift
//  PostHog
//
//  Created by Yiannis Josephides on 11/11/2024.
//

#if os(iOS) || os(tvOS)
    import UIKit

    extension UIApplication {
        static func getCurrentWindow(filterForegrounded: Bool = true) -> UIWindow? {
            let windowScenes = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter {
                    !filterForegrounded || $0.activationState == .foregroundActive
                }

            if #available(iOS 15.0, tvOS 15.0, *) {
                // attempt to retrieve directly from UIWindowScene
                if let keyWindow = windowScenes.compactMap(\.keyWindow).first {
                    return keyWindow
                }
            }

            // fall back to iterating for `isKeyWindow`
            return windowScenes
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow })
        }
    }
#endif
