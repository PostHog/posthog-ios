import Foundation
import ObjectiveC

/// Swizzle URLSession(configuration:) initializer to inject our RequestInterceptor
class URLSessionSwizzler {
    private static let swizzleOnce: Void = {
        let originalSelector = #selector(URLSession.init(configuration:))
        let swizzledSelector = #selector(URLSession.init(swizzled_configuration:))

        guard let originalMethod = class_getInstanceMethod(URLSession.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(URLSession.self, swizzledSelector)
        else {
            print("[SWIZZLE] Failed to get methods for swizzling")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
        print("[SWIZZLE] URLSession.init(configuration:) swizzled successfully")
    }()

    static func install() {
        _ = swizzleOnce
    }
}

extension URLSession {
    @objc convenience init(swizzled_configuration configuration: URLSessionConfiguration) {
        // Inject our interceptor
        var protocols = configuration.protocolClasses ?? []
        if !protocols.contains(where: { $0 == RequestInterceptor.self }) {
            protocols.insert(RequestInterceptor.self, at: 0)
            configuration.protocolClasses = protocols
            print("[SWIZZLE] Injected RequestInterceptor into URLSession configuration")
        }

        // Call the original init (which is now swizzled_configuration due to exchange)
        self.init(swizzled_configuration: configuration)
    }
}
