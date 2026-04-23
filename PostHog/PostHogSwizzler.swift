//
//  PostHogSwizzler.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 26.03.24.
//

import Foundation

/// Exchange implementations of two methods on a class.
/// Calling again with the same arguments reverses the swizzle.
func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}

/// Swizzle a method on `targetClass`, handling the case where the class
/// may not implement the original selector yet.
///
/// If the target class already implements `original`, the implementations are exchanged.
/// If it does not, the swizzled implementation is added under `original`, and a no-op
/// is added under `swizzled` so call-throughs don't recurse.
///
/// - Parameters:
///   - targetClass: The class to swizzle.
///   - original: The original selector to intercept.
///   - swizzled: The selector whose implementation (on `sourceClass`) will replace the original.
///   - sourceClass: The class containing the swizzled method implementation. Defaults to `NSObject.self`.
func swizzleAddingIfNeeded(on targetClass: AnyClass, original: Selector, swizzled: Selector, sourceClass: AnyClass = NSObject.self) {
    guard let swizzledMethod = class_getInstanceMethod(sourceClass, swizzled) else {
        hedgeLog("Swizzle failed: method not found for \(swizzled)")
        return
    }

    if let originalMethod = class_getInstanceMethod(targetClass, original) {
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
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    } else {
        // Target class doesn't implement the method — add our version under the original selector
        class_addMethod(
            targetClass,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        // Add a no-op under the swizzled selector so the call-through doesn't recurse
        let noopBlock: @convention(block) () -> Void = {}
        let noopImp = imp_implementationWithBlock(noopBlock)
        class_addMethod(
            targetClass,
            swizzled,
            noopImp,
            method_getTypeEncoding(swizzledMethod)
        )
    }
}
