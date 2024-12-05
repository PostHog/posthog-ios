//
//  UIWindow+.swift
//  PostHog
//
//  Created by Yiannis Josephides on 03/12/2024.
//

#if os(iOS) || os(tvOS)
    import Foundation
    import UIKit

    extension UIWindow {
        var isKeyboardWindow: Bool {
            String(describing: type(of: window)) == "UIRemoteKeyboardWindow"
        }
    }
#endif
