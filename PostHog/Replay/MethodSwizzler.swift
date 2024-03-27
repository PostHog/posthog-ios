/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
    import Foundation

    class MethodSwizzler<TypedIMP, TypedBlockIMP> {
        struct FoundMethod: Hashable {
            let method: Method
            private let klass: AnyClass

            fileprivate init(method: Method, klass: AnyClass) {
                self.method = method
                self.klass = klass
            }

            static func == (lhs: FoundMethod, rhs: FoundMethod) -> Bool {
                let methodParity = (lhs.method == rhs.method)
                let classParity = (NSStringFromClass(lhs.klass) == NSStringFromClass(rhs.klass))
                return methodParity && classParity
            }

            func hash(into hasher: inout Hasher) {
                let methodName = NSStringFromSelector(method_getName(method))
                let klassName = NSStringFromClass(klass)
                let identifier = "\(methodName)|||\(klassName)"
                hasher.combine(identifier)
            }
        }

        private var implementationCache: [FoundMethod: IMP] = [:]
        var swizzledMethods: [FoundMethod] {
            Array(implementationCache.keys)
        }

        static func findMethod(with selector: Selector, in klass: AnyClass) throws -> FoundMethod {
            /// NOTE: RUMM-452 as we never add/remove methods/classes at runtime,
            /// search operation doesn't have to wrapped in sync {...} although it's visible in the interface
            var headKlass: AnyClass? = klass
            while let someKlass = headKlass {
                if let foundMethod = findMethod(with: selector, in: someKlass) {
                    return FoundMethod(method: foundMethod, klass: someKlass)
                }
                headKlass = class_getSuperclass(headKlass)
            }
            throw InternalPostHogError(description: "\(NSStringFromSelector(selector)) is not found in \(NSStringFromClass(klass))")
        }

        func originalImplementation(of found: FoundMethod) -> TypedIMP {
            sync {
                let originalImp: IMP = implementationCache[found] ?? method_getImplementation(found.method)
                return unsafeBitCast(originalImp, to: TypedIMP.self)
            }
        }

        func swizzle(
            _ foundMethod: FoundMethod,
            impProvider: (TypedIMP) -> TypedBlockIMP
        ) {
            sync {
                let currentIMP = method_getImplementation(foundMethod.method)
                let currentTypedIMP = unsafeBitCast(currentIMP, to: TypedIMP.self)
                let newImpBlock: TypedBlockIMP = impProvider(currentTypedIMP)
                let newImp: IMP = imp_implementationWithBlock(newImpBlock)

                set(newIMP: newImp, for: foundMethod)
            }
        }

        /// Removes swizzling and resets the method to its original implementation.
        func unswizzle() {
            for foundMethod in swizzledMethods {
                let originalTypedIMP = originalImplementation(of: foundMethod)
                let originalIMP: IMP = unsafeBitCast(originalTypedIMP, to: IMP.self)
                method_setImplementation(foundMethod.method, originalIMP)
            }
        }

        // MARK: - Private methods

        @discardableResult
        private func sync<T>(block: () -> T) -> T {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            return block()
        }

        private static func findMethod(with selector: Selector, in klass: AnyClass) -> Method? {
            var methodsCount: UInt32 = 0
            let methodsCountPtr = withUnsafeMutablePointer(to: &methodsCount) { $0 }
            guard let methods: UnsafeMutablePointer<Method> = class_copyMethodList(klass, methodsCountPtr) else {
                return nil
            }
            defer {
                free(methods)
            }
            for index in 0 ..< Int(methodsCount) {
                let method = methods.advanced(by: index).pointee
                if method_getName(method) == selector {
                    return method
                }
            }
            return nil
        }

        private func set(newIMP: IMP, for found: FoundMethod) {
            if implementationCache[found] == nil {
                implementationCache[found] = method_getImplementation(found.method)
            }
            method_setImplementation(found.method, newIMP)
        }
    }

    extension MethodSwizzler.FoundMethod {
        var swizzlingName: String { "\(klass).\(method_getName(method))" }
    }
#endif
