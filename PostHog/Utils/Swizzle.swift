//
//  Swizzle.swift
//  PostHog
//
//  Created by Ben White on 16.02.23.
//

import Foundation

func swizzle(selector originalSelector: Selector, with swizzledSelector: Selector, inClass: AnyClass, usingClass: AnyClass) {
    guard let originalMethod = class_getInstanceMethod(inClass, originalSelector),
          let swizzledMethod = class_getInstanceMethod(usingClass, swizzledSelector)
    else { return }

    if class_addMethod(inClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod)) {
        class_replaceMethod(inClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}
