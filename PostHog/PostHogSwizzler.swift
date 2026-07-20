//
//  PostHogSwizzler.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 26.03.24.
//

import Foundation

/// Exchanges the implementations of two methods on a class.
/// Calling again with the same arguments reverses the swizzle.
func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}

/// Swizzles `original` on `targetClass`, adding the method first when the class doesn't implement it.
///
/// Host app delegates frequently omit the push-notification selectors, so a plain
/// `method_exchangeImplementations` would find nothing to exchange. When `original` is missing we add
/// our implementation under it and register a no-op under `swizzled` so the call-through can't recurse.
///
/// - Parameters:
///   - targetClass: The class to swizzle.
///   - original: The selector to intercept.
///   - swizzled: The selector whose implementation (on `sourceClass`) replaces the original.
///   - sourceClass: The class defining the swizzled implementation. Defaults to `NSObject`.
///   - noop: Optional selector (on `sourceClass`) whose implementation backs the call-through when
///     `original` was missing. Use it when doing nothing is wrong — e.g. a method that receives a
///     completion handler the system expects to be invoked. Defaults to an empty block.
func swizzleAddingIfNeeded(on targetClass: AnyClass, original: Selector, swizzled: Selector, sourceClass: AnyClass = NSObject.self, noop: Selector? = nil) {
    guard let swizzledMethod = class_getInstanceMethod(sourceClass, swizzled) else {
        hedgeLog("Swizzle failed: method not found for \(swizzled)")
        return
    }

    guard let originalMethod = class_getInstanceMethod(targetClass, original) else {
        // Target class doesn't implement the method — add our version under the original selector
        class_addMethod(
            targetClass,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        // Register a call-through under the swizzled selector so the added method can't recurse
        if let noop, let noopMethod = class_getInstanceMethod(sourceClass, noop) {
            class_addMethod(
                targetClass,
                swizzled,
                method_getImplementation(noopMethod),
                method_getTypeEncoding(noopMethod)
            )
        } else {
            let noopBlock: @convention(block) () -> Void = {}
            class_addMethod(
                targetClass,
                swizzled,
                imp_implementationWithBlock(noopBlock),
                method_getTypeEncoding(swizzledMethod)
            )
        }
        return
    }

    let didAdd = class_addMethod(
        targetClass,
        swizzled,
        method_getImplementation(originalMethod),
        method_getTypeEncoding(originalMethod)
    )
    if didAdd {
        class_replaceMethod(
            targetClass,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
    } else if let targetSwizzledMethod = class_getInstanceMethod(targetClass, swizzled) {
        // didAdd == false means targetClass itself already owns an entry for `swizzled` (a previous
        // install/uninstall cycle left it there). Exchange with that entry — exchanging with
        // `swizzledMethod` (sourceClass's Method) would corrupt sourceClass for every other class
        // and leave the call-through pointing at itself, recursing on the next invocation.
        method_exchangeImplementations(originalMethod, targetSwizzledMethod)
    }
}
