// swiftlint:disable nesting

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

    import Foundation

    class URLSessionSwizzler {
        /// `URLSession.dataTask(with:completionHandler:)` (for `URLRequest`) swizzling.
        private let dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion
        /// `URLSession.dataTask(with:)` (for `URLRequest`) swizzling.
        private let dataTaskWithURLRequest: DataTaskWithURLRequest

        /// `URLSession.dataTask(with:completionHandler:)` (for `URL`) swizzling. Only applied on iOS 13 and above.
        private let dataTaskWithURLAndCompletion: DataTaskWithURLAndCompletion?
        /// `URLSession.dataTask(with:)` (for `URL`) swizzling. Only applied on iOS 13 and above.
        private let dataTaskWithURL: DataTaskWithURL?

        private let interceptor: URLSessionInterceptor

        private var hasSwizzled = false

        init(interceptor: URLSessionInterceptor) throws {
            self.interceptor = interceptor

            dataTaskWithURLAndCompletion = try DataTaskWithURLAndCompletion.build(interceptor: interceptor)
            dataTaskWithURL = try DataTaskWithURL.build(interceptor: interceptor)

            dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion.build(interceptor: interceptor)
            dataTaskWithURLRequest = try DataTaskWithURLRequest.build(interceptor: interceptor)
        }

        func swizzle() {
            dataTaskWithURLRequestAndCompletion.swizzle()
            dataTaskWithURLAndCompletion?.swizzle()
            dataTaskWithURLRequest.swizzle()
            dataTaskWithURL?.swizzle()
            hasSwizzled = true
        }

        func unswizzle() {
            if !hasSwizzled {
                return
            }
            dataTaskWithURLRequestAndCompletion.unswizzle()
            dataTaskWithURLRequest.unswizzle()
            dataTaskWithURLAndCompletion?.unswizzle()
            dataTaskWithURL?.unswizzle()
            hasSwizzled = false
        }

        // MARK: - Swizzlings

        typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

        /// Swizzles the `URLSession.dataTask(with:completionHandler:)` for `URLRequest`.
        class DataTaskWithURLRequestAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, CompletionHandler?) -> URLSessionDataTask,
            @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let interceptor: URLSessionInterceptor

            static func build(interceptor: URLSessionInterceptor) throws -> DataTaskWithURLRequestAndCompletion {
                try DataTaskWithURLRequestAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    interceptor: interceptor
                )
            }

            private init(selector: Selector, klass: AnyClass, interceptor: URLSessionInterceptor) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.interceptor = interceptor
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, completionHandler -> URLSessionDataTask in
                    let task: URLSessionDataTask
                    if completionHandler != nil {
                        var taskReference: URLSessionDataTask?
                        let newCompletionHandler: CompletionHandler = { data, response, error in
                            if let task = taskReference { // sanity check, should always succeed
                                self.interceptor.taskCompleted(task: task, error: error)
                            }
                            completionHandler?(data, response, error)
                        }

                        task = previousImplementation(session, Self.selector, urlRequest, newCompletionHandler)
                        taskReference = task
                    } else {
                        // The `completionHandler` can be `nil` in two cases:
                        // - on iOS 11 or 12, where `dataTask(with:)` (for `URL` and `URLRequest`) calls
                        //   the `dataTask(with:completionHandler:)` (for `URLRequest`) internally by nullifying the completion block.
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
                        task = previousImplementation(session, Self.selector, urlRequest, completionHandler)
                    }
                    self.interceptor.taskCreated(task: task, session: session)
                    return task
                }
                }
            }
        }

        /// Swizzles the `URLSession.dataTask(with:completionHandler:)` for `URL`.
        class DataTaskWithURLAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URL, CompletionHandler?) -> URLSessionDataTask,
            @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let interceptor: URLSessionInterceptor

            static func build(interceptor: URLSessionInterceptor) throws -> DataTaskWithURLAndCompletion {
                try DataTaskWithURLAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    interceptor: interceptor
                )
            }

            private init(selector: Selector, klass: AnyClass, interceptor: URLSessionInterceptor) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.interceptor = interceptor
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask
                swizzle(method) { previousImplementation -> Signature in { session, url, completionHandler -> URLSessionDataTask in
                    let task: URLSessionDataTask
                    if completionHandler != nil {
                        var taskReference: URLSessionDataTask?
                        let newCompletionHandler: CompletionHandler = { data, response, error in
                            if let task = taskReference { // sanity check, should always succeed
                                self.interceptor.taskCompleted(task: task, error: error)
                            }
                            completionHandler?(data, response, error)
                        }
                        task = previousImplementation(session, Self.selector, url, newCompletionHandler)
                        taskReference = task
                    } else {
                        // The `completionHandler` can be `nil` in one case:
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
                        task = previousImplementation(session, Self.selector, url, completionHandler)
                    }
                    self.interceptor.taskCreated(task: task, session: session)
                    return task
                }
                }
            }
        }

        /// Swizzles the `URLSession.dataTask(with:)` for `URLRequest`.
        class DataTaskWithURLRequest: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest) -> URLSessionDataTask,
            @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let interceptor: URLSessionInterceptor

            static func build(interceptor: URLSessionInterceptor) throws -> DataTaskWithURLRequest {
                try DataTaskWithURLRequest(
                    selector: selector,
                    klass: URLSession.self,
                    interceptor: interceptor
                )
            }

            private init(selector: Selector, klass: AnyClass, interceptor: URLSessionInterceptor) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.interceptor = interceptor
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest -> URLSessionDataTask in
                    let task = previousImplementation(session, Self.selector, urlRequest)
                    self.interceptor.taskCreated(task: task, session: session)
                    return task
                }
                }
            }
        }

        /// Swizzles the `URLSession.dataTask(with:)` for `URL`.
        class DataTaskWithURL: MethodSwizzler<
            @convention(c) (URLSession, Selector, URL) -> URLSessionDataTask,
            @convention(block) (URLSession, URL) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let interceptor: URLSessionInterceptor

            static func build(interceptor: URLSessionInterceptor) throws -> DataTaskWithURL {
                try DataTaskWithURL(
                    selector: selector,
                    klass: URLSession.self,
                    interceptor: interceptor
                )
            }

            private init(selector: Selector, klass: AnyClass, interceptor: URLSessionInterceptor) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.interceptor = interceptor
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URL) -> URLSessionDataTask
                swizzle(method) { previousImplementation -> Signature in { session, url -> URLSessionDataTask in
                    let task = previousImplementation(session, Self.selector, url)
                    self.interceptor.taskCreated(task: task, session: session)
                    return task
                }
                }
            }
        }
    }

#endif

// swiftlint:enable nesting
