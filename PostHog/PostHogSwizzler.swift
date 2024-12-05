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

func swizzleClassMethod(forClass: AnyClass, original: Selector, new: Selector) {
    guard let c = object_getClass(forClass) else { return }
    guard let originalMethod = class_getClassMethod(c, original) else { return }
    guard let swizzledMethod = class_getClassMethod(c, new) else { return }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}
