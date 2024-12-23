//
//  UIWindow+.swift
//  PostHog
//
//  Created by Yiannis Josephides on 03/12/2024.
//

#if os(iOS) || os(tvOS)
    import Foundation
    import UIKit

    /**
     Known keyboard window (private) types

     ## UIRemoteKeyboardWindow
     This is the window that manages the actual keyboard

     The following system view controllers were observed to be presented in a UIRemoteKeyboardWindow window
        - UIInputWindowController
        - UICompatibilityInputViewController
        - UISystemInputAssistantViewController
        - UIPredictionViewController
        - UISystemKeyboardDockController
        - TUIEmojiSearchInputViewController
        - STKPrewarmingViewController
        - STKStickerRemoteSearchViewController
        - _UIRemoteInputViewController
        - _UISceneHostingViewController
        - STKEmojiAndStickerCollectionViewController

     ## UITextEffectsWindow
     Hosts system components like the magnifying glass for text selection, predictive text suggestions, copy/paste menus, input accessory views etc.

     The following system view controllers were observed to be presented in a UITextEffectsWindow window
        - UIInputWindowController
        - UICompatibilityInputViewController

     These view controllers should not appear in a $screen event. If they do, then it means that they are presented in a UIWindow not listed below
     */
    private let knownKeyboardWindowTypes: [String] = [
        "UIRemoteKeyboardWindow",
        "UITextEffectsWindow",
    ]

    extension UIWindow {
        var isKeyboardWindow: Bool {
            knownKeyboardWindowTypes.contains(String(describing: type(of: self)))
        }
    }
#endif
