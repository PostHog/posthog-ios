//
//  PostHogSwizzler.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 26.03.24.
//

import Foundation

func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}
