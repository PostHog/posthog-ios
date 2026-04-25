// swiftlint:disable nesting

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

    import Foundation

    final class URLSessionInstrumentation {
        typealias RequestModifier = (URLRequest) -> URLRequest
        typealias TaskCreatedHandler = (URLSessionTask, URLSession?) -> Void
        typealias TaskCompletedHandler = (URLSessionTask, Error?) -> Void

        static let shared = URLSessionInstrumentation()

        private static let requestModifiedKey = "com.posthog.URLSessionInstrumentation.requestModified"

        private struct Registration {
            let requestModifier: RequestModifier?
            let taskCreated: TaskCreatedHandler?
            let taskCompleted: TaskCompletedHandler?
        }

        private let lock = NSLock()
        private var registrations: [UUID: Registration] = [:]
        private var swizzler: URLSessionSwizzler?

        private init() {}

        func register(
            requestModifier: RequestModifier? = nil,
            taskCreated: TaskCreatedHandler? = nil,
            taskCompleted: TaskCompletedHandler? = nil
        ) throws -> UUID {
            let id = UUID()
            let registration = Registration(
                requestModifier: requestModifier,
                taskCreated: taskCreated,
                taskCompleted: taskCompleted
            )

            let shouldInstallSwizzler = lock.withLock {
                let shouldInstall = registrations.isEmpty
                registrations[id] = registration
                return shouldInstall
            }

            guard shouldInstallSwizzler else {
                return id
            }

            do {
                let swizzler = try URLSessionSwizzler(
                    modifyRequest: { [weak self] request in
                        self?.modifyRequest(request) ?? request
                    },
                    onTaskCreated: { [weak self] task, session in
                        self?.notifyTaskCreated(task: task, session: session)
                    },
                    onTaskCompleted: { [weak self] task, error in
                        self?.notifyTaskCompleted(task: task, error: error)
                    }
                )
                swizzler.swizzle()
                lock.withLock {
                    self.swizzler = swizzler
                }
                return id
            } catch {
                lock.withLock {
                    registrations.removeValue(forKey: id)
                }
                throw error
            }
        }

        func unregister(_ id: UUID) {
            var swizzlerToRemove: URLSessionSwizzler?

            lock.withLock {
                registrations.removeValue(forKey: id)
                if registrations.isEmpty {
                    swizzlerToRemove = swizzler
                    swizzler = nil
                }
            }

            swizzlerToRemove?.unswizzle()
        }

        private func modifyRequest(_ request: URLRequest) -> URLRequest {
            guard URLProtocol.property(forKey: Self.requestModifiedKey, in: request) == nil else {
                return request
            }

            let modifiers = lock.withLock {
                registrations.values.compactMap(\.requestModifier)
            }

            guard !modifiers.isEmpty else {
                return request
            }

            let modifiedRequest = modifiers.reduce(request) { currentRequest, modifier in
                modifier(currentRequest)
            }

            guard let mutableRequest = (modifiedRequest as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
                return modifiedRequest
            }

            URLProtocol.setProperty(true, forKey: Self.requestModifiedKey, in: mutableRequest)
            return mutableRequest as URLRequest
        }

        private func notifyTaskCreated(task: URLSessionTask, session: URLSession?) {
            let handlers = lock.withLock {
                registrations.values.compactMap(\.taskCreated)
            }

            for handler in handlers {
                handler(task, session)
            }
        }

        private func notifyTaskCompleted(task: URLSessionTask, error: Error?) {
            let handlers = lock.withLock {
                registrations.values.compactMap(\.taskCompleted)
            }

            for handler in handlers {
                handler(task, error)
            }
        }
    }

    class URLSessionSwizzler {
        typealias DataCompletionHandler = (Data?, URLResponse?, Error?) -> Void
        typealias DownloadCompletionHandler = (URL?, URLResponse?, Error?) -> Void

        private let dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion
        private let dataTaskWithURLRequest: DataTaskWithURLRequest
        private let dataTaskWithURLAndCompletion: DataTaskWithURLAndCompletion
        private let dataTaskWithURL: DataTaskWithURL

        private let uploadTaskWithRequestAndDataAndCompletion: UploadTaskWithRequestAndDataAndCompletion
        private let uploadTaskWithRequestAndFileAndCompletion: UploadTaskWithRequestAndFileAndCompletion
        private let uploadTaskWithStreamedRequest: UploadTaskWithStreamedRequest
        private let uploadTaskWithRequestAndData: UploadTaskWithRequestAndData
        private let uploadTaskWithRequestAndFile: UploadTaskWithRequestAndFile

        private let downloadTaskWithRequestAndCompletion: DownloadTaskWithRequestAndCompletion
        private let downloadTaskWithURLAndCompletion: DownloadTaskWithURLAndCompletion
        private let downloadTaskWithRequest: DownloadTaskWithRequest
        private let downloadTaskWithURL: DownloadTaskWithURL
        private let taskResume: TaskResume?

        private var hasSwizzled = false

        init(
            modifyRequest: @escaping (URLRequest) -> URLRequest,
            onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
            onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
        ) throws {
            dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated,
                onTaskCompleted: onTaskCompleted
            )
            dataTaskWithURLRequest = try DataTaskWithURLRequest.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated
            )
            dataTaskWithURLAndCompletion = try DataTaskWithURLAndCompletion.build(modifyRequest: modifyRequest)
            dataTaskWithURL = try DataTaskWithURL.build(modifyRequest: modifyRequest)

            uploadTaskWithRequestAndDataAndCompletion = try UploadTaskWithRequestAndDataAndCompletion.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated,
                onTaskCompleted: onTaskCompleted
            )
            uploadTaskWithRequestAndFileAndCompletion = try UploadTaskWithRequestAndFileAndCompletion.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated,
                onTaskCompleted: onTaskCompleted
            )
            uploadTaskWithStreamedRequest = try UploadTaskWithStreamedRequest.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated
            )
            uploadTaskWithRequestAndData = try UploadTaskWithRequestAndData.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated
            )
            uploadTaskWithRequestAndFile = try UploadTaskWithRequestAndFile.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated
            )

            downloadTaskWithRequestAndCompletion = try DownloadTaskWithRequestAndCompletion.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated,
                onTaskCompleted: onTaskCompleted
            )
            downloadTaskWithURLAndCompletion = try DownloadTaskWithURLAndCompletion.build(modifyRequest: modifyRequest)
            downloadTaskWithRequest = try DownloadTaskWithRequest.build(
                modifyRequest: modifyRequest,
                onTaskCreated: onTaskCreated
            )
            downloadTaskWithURL = try DownloadTaskWithURL.build(modifyRequest: modifyRequest)

            // Async/await URLSession convenience APIs are iOS 15+, so only install the
            // task-level resume fallback on those OS versions.
            if #available(iOS 15, *) {
                taskResume = try TaskResume.build(modifyRequest: modifyRequest)
            } else {
                taskResume = nil
            }
        }

        func swizzle() {
            dataTaskWithURLRequestAndCompletion.swizzle()
            dataTaskWithURLRequest.swizzle()
            dataTaskWithURLAndCompletion.swizzle()
            dataTaskWithURL.swizzle()

            uploadTaskWithRequestAndDataAndCompletion.swizzle()
            uploadTaskWithRequestAndFileAndCompletion.swizzle()
            uploadTaskWithStreamedRequest.swizzle()
            uploadTaskWithRequestAndData.swizzle()
            uploadTaskWithRequestAndFile.swizzle()

            downloadTaskWithRequestAndCompletion.swizzle()
            downloadTaskWithURLAndCompletion.swizzle()
            downloadTaskWithRequest.swizzle()
            downloadTaskWithURL.swizzle()
            taskResume?.swizzle()

            hasSwizzled = true
        }

        func unswizzle() {
            if !hasSwizzled {
                return
            }

            dataTaskWithURLRequestAndCompletion.unswizzle()
            dataTaskWithURLRequest.unswizzle()
            dataTaskWithURLAndCompletion.unswizzle()
            dataTaskWithURL.unswizzle()

            uploadTaskWithRequestAndDataAndCompletion.unswizzle()
            uploadTaskWithRequestAndFileAndCompletion.unswizzle()
            uploadTaskWithStreamedRequest.unswizzle()
            uploadTaskWithRequestAndData.unswizzle()
            uploadTaskWithRequestAndFile.unswizzle()

            downloadTaskWithRequestAndCompletion.unswizzle()
            downloadTaskWithURLAndCompletion.unswizzle()
            downloadTaskWithRequest.unswizzle()
            downloadTaskWithURL.unswizzle()
            taskResume?.unswizzle()

            hasSwizzled = false
        }

        class TaskResume: MethodSwizzler<
            @convention(c) (URLSessionTask, Selector) -> Void,
            @convention(block) (URLSessionTask) -> Void
        > {
            private static let selector = #selector(URLSessionTask.resume)
            private static let currentRequestKey = "currentRequest"

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest

            static func build(modifyRequest: @escaping (URLRequest) -> URLRequest) throws -> TaskResume {
                try TaskResume(
                    selector: selector,
                    klass: URLSessionTask.self,
                    modifyRequest: modifyRequest
                )
            }

            private init(selector: Selector, klass: AnyClass, modifyRequest: @escaping (URLRequest) -> URLRequest) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSessionTask) -> Void
                swizzle(method) { previousImplementation -> Signature in { task in
                    self.modifyTaskRequests(task)
                    previousImplementation(task, Self.selector)
                }
                }
            }

            private func modifyTaskRequests(_ task: URLSessionTask) {
                // Only rewrite `currentRequest` for the async/await fallback path.
                // This is the request closest to what will go over the wire and avoids
                // mutating `originalRequest` unnecessarily. Use KVC instead of invoking
                // a private setter selector directly.
                if let currentRequest = task.currentRequest {
                    task.setValue(modifyRequest(currentRequest) as NSURLRequest, forKey: Self.currentRequestKey)
                }
            }
        }

        // MARK: - Data tasks

        class DataTaskWithURLRequestAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, DataCompletionHandler?) -> URLSessionDataTask,
            @convention(block) (URLSession, URLRequest, DataCompletionHandler?) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping DataCompletionHandler) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void
            private let onTaskCompleted: (URLSessionTask, Error?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws -> DataTaskWithURLRequestAndCompletion {
                try DataTaskWithURLRequestAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated,
                    onTaskCompleted: onTaskCompleted
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                self.onTaskCompleted = onTaskCompleted
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, DataCompletionHandler?) -> URLSessionDataTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, completionHandler -> URLSessionDataTask in
                    let modifiedRequest = self.modifyRequest(urlRequest)
                    let task: URLSessionDataTask

                    if completionHandler != nil {
                        var taskReference: URLSessionDataTask?
                        let newCompletionHandler: DataCompletionHandler = { data, response, error in
                            if let task = taskReference {
                                self.onTaskCompleted(task, error)
                            }
                            completionHandler?(data, response, error)
                        }

                        task = previousImplementation(session, Self.selector, modifiedRequest, newCompletionHandler)
                        taskReference = task
                    } else {
                        task = previousImplementation(session, Self.selector, modifiedRequest, completionHandler)
                    }

                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class DataTaskWithURLRequest: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest) -> URLSessionDataTask,
            @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws -> DataTaskWithURLRequest {
                try DataTaskWithURLRequest(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest -> URLSessionDataTask in
                    let task = previousImplementation(session, Self.selector, self.modifyRequest(urlRequest))
                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class DataTaskWithURLAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URL, DataCompletionHandler?) -> URLSessionDataTask,
            @convention(block) (URLSession, URL, DataCompletionHandler?) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping DataCompletionHandler) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest

            static func build(modifyRequest: @escaping (URLRequest) -> URLRequest) throws -> DataTaskWithURLAndCompletion {
                try DataTaskWithURLAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest
                )
            }

            private init(selector: Selector, klass: AnyClass, modifyRequest: @escaping (URLRequest) -> URLRequest) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URL, DataCompletionHandler?) -> URLSessionDataTask
                swizzle(method) { _ -> Signature in { session, url, completionHandler -> URLSessionDataTask in
                    let request = self.modifyRequest(URLRequest(url: url))
                    if let completionHandler {
                        return session.dataTask(with: request, completionHandler: completionHandler)
                    }
                    return session.dataTask(with: request)
                }
                }
            }
        }

        class DataTaskWithURL: MethodSwizzler<
            @convention(c) (URLSession, Selector, URL) -> URLSessionDataTask,
            @convention(block) (URLSession, URL) -> URLSessionDataTask
        > {
            private static let selector = #selector(
                URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest

            static func build(modifyRequest: @escaping (URLRequest) -> URLRequest) throws -> DataTaskWithURL {
                try DataTaskWithURL(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest
                )
            }

            private init(selector: Selector, klass: AnyClass, modifyRequest: @escaping (URLRequest) -> URLRequest) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URL) -> URLSessionDataTask
                swizzle(method) { _ -> Signature in { session, url -> URLSessionDataTask in
                    session.dataTask(with: self.modifyRequest(URLRequest(url: url)))
                }
                }
            }
        }

        // MARK: - Upload tasks

        class UploadTaskWithRequestAndDataAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, Data?, DataCompletionHandler?) -> URLSessionUploadTask,
            @convention(block) (URLSession, URLRequest, Data?, DataCompletionHandler?) -> URLSessionUploadTask
        > {
            private static let selector = #selector(
                URLSession.uploadTask(with:from:completionHandler:) as (URLSession) -> (URLRequest, Data?, @escaping DataCompletionHandler) -> URLSessionUploadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void
            private let onTaskCompleted: (URLSessionTask, Error?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws -> UploadTaskWithRequestAndDataAndCompletion {
                try UploadTaskWithRequestAndDataAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated,
                    onTaskCompleted: onTaskCompleted
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                self.onTaskCompleted = onTaskCompleted
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, Data?, DataCompletionHandler?) -> URLSessionUploadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, bodyData, completionHandler -> URLSessionUploadTask in
                    let modifiedRequest = self.modifyRequest(urlRequest)
                    let task: URLSessionUploadTask

                    if completionHandler != nil {
                        var taskReference: URLSessionUploadTask?
                        let newCompletionHandler: DataCompletionHandler = { data, response, error in
                            if let task = taskReference {
                                self.onTaskCompleted(task, error)
                            }
                            completionHandler?(data, response, error)
                        }

                        task = previousImplementation(session, Self.selector, modifiedRequest, bodyData, newCompletionHandler)
                        taskReference = task
                    } else {
                        task = previousImplementation(session, Self.selector, modifiedRequest, bodyData, completionHandler)
                    }

                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class UploadTaskWithRequestAndFileAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, URL, DataCompletionHandler?) -> URLSessionUploadTask,
            @convention(block) (URLSession, URLRequest, URL, DataCompletionHandler?) -> URLSessionUploadTask
        > {
            private static let selector = #selector(
                URLSession.uploadTask(with:fromFile:completionHandler:) as (URLSession) -> (URLRequest, URL, @escaping DataCompletionHandler) -> URLSessionUploadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void
            private let onTaskCompleted: (URLSessionTask, Error?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws -> UploadTaskWithRequestAndFileAndCompletion {
                try UploadTaskWithRequestAndFileAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated,
                    onTaskCompleted: onTaskCompleted
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                self.onTaskCompleted = onTaskCompleted
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, URL, DataCompletionHandler?) -> URLSessionUploadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, fileURL, completionHandler -> URLSessionUploadTask in
                    let modifiedRequest = self.modifyRequest(urlRequest)
                    let task: URLSessionUploadTask

                    if completionHandler != nil {
                        var taskReference: URLSessionUploadTask?
                        let newCompletionHandler: DataCompletionHandler = { data, response, error in
                            if let task = taskReference {
                                self.onTaskCompleted(task, error)
                            }
                            completionHandler?(data, response, error)
                        }

                        task = previousImplementation(session, Self.selector, modifiedRequest, fileURL, newCompletionHandler)
                        taskReference = task
                    } else {
                        task = previousImplementation(session, Self.selector, modifiedRequest, fileURL, completionHandler)
                    }

                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class UploadTaskWithStreamedRequest: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest) -> URLSessionUploadTask,
            @convention(block) (URLSession, URLRequest) -> URLSessionUploadTask
        > {
            private static let selector = #selector(
                URLSession.uploadTask(withStreamedRequest:) as (URLSession) -> (URLRequest) -> URLSessionUploadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws -> UploadTaskWithStreamedRequest {
                try UploadTaskWithStreamedRequest(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionUploadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest -> URLSessionUploadTask in
                    let task = previousImplementation(session, Self.selector, self.modifyRequest(urlRequest))
                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class UploadTaskWithRequestAndData: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, Data) -> URLSessionUploadTask,
            @convention(block) (URLSession, URLRequest, Data) -> URLSessionUploadTask
        > {
            private static let selector = #selector(
                URLSession.uploadTask(with:from:) as (URLSession) -> (URLRequest, Data) -> URLSessionUploadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws -> UploadTaskWithRequestAndData {
                try UploadTaskWithRequestAndData(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, Data) -> URLSessionUploadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, bodyData -> URLSessionUploadTask in
                    let task = previousImplementation(session, Self.selector, self.modifyRequest(urlRequest), bodyData)
                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class UploadTaskWithRequestAndFile: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, URL) -> URLSessionUploadTask,
            @convention(block) (URLSession, URLRequest, URL) -> URLSessionUploadTask
        > {
            private static let selector = #selector(
                URLSession.uploadTask(with:fromFile:) as (URLSession) -> (URLRequest, URL) -> URLSessionUploadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws -> UploadTaskWithRequestAndFile {
                try UploadTaskWithRequestAndFile(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, URL) -> URLSessionUploadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, fileURL -> URLSessionUploadTask in
                    let task = previousImplementation(session, Self.selector, self.modifyRequest(urlRequest), fileURL)
                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        // MARK: - Download tasks

        class DownloadTaskWithRequestAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest, DownloadCompletionHandler?) -> URLSessionDownloadTask,
            @convention(block) (URLSession, URLRequest, DownloadCompletionHandler?) -> URLSessionDownloadTask
        > {
            private static let selector = #selector(
                URLSession.downloadTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping DownloadCompletionHandler) -> URLSessionDownloadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void
            private let onTaskCompleted: (URLSessionTask, Error?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws -> DownloadTaskWithRequestAndCompletion {
                try DownloadTaskWithRequestAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated,
                    onTaskCompleted: onTaskCompleted
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void,
                onTaskCompleted: @escaping (URLSessionTask, Error?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                self.onTaskCompleted = onTaskCompleted
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest, DownloadCompletionHandler?) -> URLSessionDownloadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest, completionHandler -> URLSessionDownloadTask in
                    let modifiedRequest = self.modifyRequest(urlRequest)
                    let task: URLSessionDownloadTask

                    if completionHandler != nil {
                        var taskReference: URLSessionDownloadTask?
                        let newCompletionHandler: DownloadCompletionHandler = { url, response, error in
                            if let task = taskReference {
                                self.onTaskCompleted(task, error)
                            }
                            completionHandler?(url, response, error)
                        }

                        task = previousImplementation(session, Self.selector, modifiedRequest, newCompletionHandler)
                        taskReference = task
                    } else {
                        task = previousImplementation(session, Self.selector, modifiedRequest, completionHandler)
                    }

                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class DownloadTaskWithURLAndCompletion: MethodSwizzler<
            @convention(c) (URLSession, Selector, URL, DownloadCompletionHandler?) -> URLSessionDownloadTask,
            @convention(block) (URLSession, URL, DownloadCompletionHandler?) -> URLSessionDownloadTask
        > {
            private static let selector = #selector(
                URLSession.downloadTask(with:completionHandler:) as (URLSession) -> (URL, @escaping DownloadCompletionHandler) -> URLSessionDownloadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest

            static func build(modifyRequest: @escaping (URLRequest) -> URLRequest) throws -> DownloadTaskWithURLAndCompletion {
                try DownloadTaskWithURLAndCompletion(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest
                )
            }

            private init(selector: Selector, klass: AnyClass, modifyRequest: @escaping (URLRequest) -> URLRequest) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URL, DownloadCompletionHandler?) -> URLSessionDownloadTask
                swizzle(method) { _ -> Signature in { session, url, completionHandler -> URLSessionDownloadTask in
                    let request = self.modifyRequest(URLRequest(url: url))
                    if let completionHandler {
                        return session.downloadTask(with: request, completionHandler: completionHandler)
                    }
                    return session.downloadTask(with: request)
                }
                }
            }
        }

        class DownloadTaskWithRequest: MethodSwizzler<
            @convention(c) (URLSession, Selector, URLRequest) -> URLSessionDownloadTask,
            @convention(block) (URLSession, URLRequest) -> URLSessionDownloadTask
        > {
            private static let selector = #selector(
                URLSession.downloadTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDownloadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest
            private let onTaskCreated: (URLSessionTask, URLSession?) -> Void

            static func build(
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws -> DownloadTaskWithRequest {
                try DownloadTaskWithRequest(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest,
                    onTaskCreated: onTaskCreated
                )
            }

            private init(
                selector: Selector,
                klass: AnyClass,
                modifyRequest: @escaping (URLRequest) -> URLRequest,
                onTaskCreated: @escaping (URLSessionTask, URLSession?) -> Void
            ) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                self.onTaskCreated = onTaskCreated
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDownloadTask
                swizzle(method) { previousImplementation -> Signature in { session, urlRequest -> URLSessionDownloadTask in
                    let task = previousImplementation(session, Self.selector, self.modifyRequest(urlRequest))
                    self.onTaskCreated(task, session)
                    return task
                }
                }
            }
        }

        class DownloadTaskWithURL: MethodSwizzler<
            @convention(c) (URLSession, Selector, URL) -> URLSessionDownloadTask,
            @convention(block) (URLSession, URL) -> URLSessionDownloadTask
        > {
            private static let selector = #selector(
                URLSession.downloadTask(with:) as (URLSession) -> (URL) -> URLSessionDownloadTask
            )

            private let method: FoundMethod
            private let modifyRequest: (URLRequest) -> URLRequest

            static func build(modifyRequest: @escaping (URLRequest) -> URLRequest) throws -> DownloadTaskWithURL {
                try DownloadTaskWithURL(
                    selector: selector,
                    klass: URLSession.self,
                    modifyRequest: modifyRequest
                )
            }

            private init(selector: Selector, klass: AnyClass, modifyRequest: @escaping (URLRequest) -> URLRequest) throws {
                method = try Self.findMethod(with: selector, in: klass)
                self.modifyRequest = modifyRequest
                super.init()
            }

            func swizzle() {
                typealias Signature = @convention(block) (URLSession, URL) -> URLSessionDownloadTask
                swizzle(method) { _ -> Signature in { session, url -> URLSessionDownloadTask in
                    session.downloadTask(with: self.modifyRequest(URLRequest(url: url)))
                }
                }
            }
        }
    }

#endif

// swiftlint:enable nesting
