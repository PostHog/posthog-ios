//
//  PostHogNetworkCaptureIntegration.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/11/2024.
//

#if os(iOS)
    import Foundation

    final class PostHogNetworkCaptureIntegration {
        private init() {}

        private static var hasSwizzled = false
        static func setupNetworkCapture() {
            guard !hasSwizzled else { return }
            hasSwizzled = true

            URLProtocol.registerClass(PostHogHTTPProtocol.self)

            PostHog.swizzleClassMethod(
                forClass: URLSessionConfiguration.self,
                original: #selector(getter: URLSessionConfiguration.default),
                new: #selector(URLSessionConfiguration.ph_swizzled_default_getter)
            )
            PostHog.swizzleClassMethod(
                forClass: URLSessionConfiguration.self,
                original: #selector(getter: URLSessionConfiguration.ephemeral),
                new: #selector(URLSessionConfiguration.ph_swizzled_ephemeral_getter)
            )
        }
    }

    private extension URLSessionConfiguration {
        @objc class func ph_swizzled_default_getter() -> URLSessionConfiguration {
            let original = ph_swizzled_default_getter()
            PostHogHTTPProtocol.enable(true, sessionConfiguration: original)
            return original
        }

        @objc class func ph_swizzled_ephemeral_getter() -> URLSessionConfiguration {
            let original = ph_swizzled_ephemeral_getter()
            PostHogHTTPProtocol.enable(true, sessionConfiguration: original)
            return original
        }
    }
#endif
