//
//  PostHogDefaultHTTPProtocol.swift
//  PostHog
//
//  Created by Yiannis Josephides on 07/11/2024.
//

#if os(iOS)
    import Foundation

    private let RequestHandledKey = "PHRequestHandled"

    /**
     URLProtocol is a part of the Foundation framework in iOS, macOS, and other Apple platforms.

     Key Methods:
       - URLProtocol has 4 key methods
         - `canInit(with:)`: Called by the system to determine whether the URLProtocol instance should handle a specific request
         - `canonicalRequest(for:)`: Called right after canInit(with:) returns true and gives us the opportunity to modify the request in any way before feeding it back to the system
         - `startLoading()`: Called to begin processing the request and do the work needed
         - `stopLoading()`: Called in the event that the request was canceled

     NOTE: `URLProtocol` implementations need to be registered by calling `URLProtocol.registerClass()` before they can be visible to the URL loading system. If a class is not registered, then `canInit(with:)` will never be called

     NOTE: `URLSessionConfiguration.protocolClasses` - The system calls `canInit(with:)` for each protocol class in the order they are listed here. Therefore, custom protocols are typically inserted at index 0 to ensure higher priority.
     */
    final class PostHogHTTPProtocol: URLProtocol {
        private var session: URLSession?
        private var sessionDataTask: URLSessionDataTask?
        private var currentSample = NetworkRequestSample()
        private var response: URLResponse?

        override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
            super.init(request: request, cachedResponse: cachedResponse, client: client)

            if session == nil {
                // ⚠️ - This is currently always using a fresh session with the `default` configuration
                //    - Need to figure out a way to use custom sessions and configurations here
                session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            }
        }

        override public class func canInit(with request: URLRequest) -> Bool {
            canHandle(request: request)
        }

        override class func canInit(with task: URLSessionTask) -> Bool {
            canHandle(task: task)
        }

        private static func canHandle(task: URLSessionTask) -> Bool {
            if #available(iOS 13.0, macOS 10.15, *) {
                // No ws support for now
                if task is URLSessionWebSocketTask {
                    return false
                }
            }

            guard let request = task.currentRequest else { return false }
            return canHandle(request: request)
        }

        private static func canHandle(request: URLRequest) -> Bool {
            guard PostHogSDK.shared.isCaptureNetworkTelemetryEnabled() else { return false }

            guard shouldHandleHost(request) else { return false }

            // check if this request has already been handled
            guard !isHandling(request: request) else { return false }

            return true
        }

        private class func shouldHandleHost(_: URLRequest) -> Bool {
            // just a placeholder for now, we could potentially choose to ignore/allow some hosts from config
            true
        }

        override public func startLoading() {
            // mark as handled
            let request = Self.markHandling(request: request)
            // collect info
            currentSample.start(request: request)
            // execute
            sessionDataTask = session?.dataTask(with: request)
            sessionDataTask?.resume()
        }

        override public func stopLoading() {
            currentSample.stop()
            sessionDataTask?.cancel()
            session?.invalidateAndCancel()
        }

        override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        deinit {
            session = nil
            sessionDataTask = nil
        }

        private func processCurrentSample() {
            var snapshotsData: [Any] = []
            let requestsData = [currentSample.toDict()]
            let payloadData: [String: Any] = [
                "requests": requestsData,
            ]
            let pluginData: [String: Any] = [
                "plugin": "rrweb/network@1",
                "payload": payloadData,
            ]

            let data: [String: Any] = [
                "type": 6,
                "data": pluginData,
                "timestamp": currentSample.timestamp,
            ]

            snapshotsData.append(data)

            PostHogSDK.shared.capture("$snapshot", properties: [
                "$snapshot_source": "mobile",
                "$snapshot_data": snapshotsData,
            ])

            currentSample.markProcessed()
        }

        private static func isHandling(request: URLRequest) -> Bool {
            property(forKey: RequestHandledKey, in: request) as? Bool ?? false
        }

        private static func markHandling(request originalRequest: URLRequest) -> URLRequest {
            let request: URLRequest
            if property(forKey: RequestHandledKey, in: originalRequest) == nil {
                let mutableRequest = originalRequest.asMutableURLRequest
                setProperty(true, forKey: RequestHandledKey, in: mutableRequest)
                request = mutableRequest as URLRequest
            } else {
                request = originalRequest
            }

            return request
        }

        private static func markNotHandling(request originalRequest: URLRequest) -> URLRequest {
            let request: URLRequest
            if property(forKey: RequestHandledKey, in: originalRequest) != nil {
                let mutableRequest = originalRequest.asMutableURLRequest
                setProperty(false, forKey: RequestHandledKey, in: mutableRequest)
                request = mutableRequest as URLRequest
            } else {
                request = originalRequest
            }

            return request
        }
    }

    extension PostHogHTTPProtocol {
        class func enable(_ enable: Bool, session: URLSession) {
            // preferredSession = session
            self.enable(enable, sessionConfiguration: session.configuration)
        }

        class func enable(_ enable: Bool, sessionConfiguration: URLSessionConfiguration) {
            var urlProtocolClasses = sessionConfiguration.protocolClasses ?? [AnyClass]()
            let phProtocolClass = Self.self

            let index = urlProtocolClasses.firstIndex(where: { obj in obj == phProtocolClass })

            if enable, index == nil { // de-duped
                urlProtocolClasses.insert(phProtocolClass, at: 0)
            } else if !enable, let index {
                urlProtocolClasses.remove(at: index)
            }

            sessionConfiguration.protocolClasses = urlProtocolClasses
        }
    }

    extension PostHogHTTPProtocol: URLSessionDataDelegate {
        public func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            hedgeLog("[Network] did receive data \(data)")
            currentSample.didReceive(data: data)
            client?.urlProtocol(self, didLoad: data)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
            let policy = URLCache.StoragePolicy(rawValue: request.cachePolicy.rawValue) ?? .notAllowed
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: policy)
            hedgeLog("[Network] did receive response \(response)")
            self.response = response

            return .allow
        }

        public func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            defer {
                if let error {
                    client?.urlProtocol(self, didFailWithError: error)
                } else {
                    client?.urlProtocolDidFinishLoading(self)
                }

                processCurrentSample()
            }

            if let response {
                currentSample.complete(response: response, error: error)
            }
        }

        public func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            hedgeLog("[Network] will perform http redirect \(response.statusCode) \(request.url?.absoluteString ?? "")")

            let theRequest = Self.markNotHandling(request: request)

            client?.urlProtocol(self, wasRedirectedTo: theRequest, redirectResponse: response)
            completionHandler(theRequest)
        }

        public func urlSession(_: URLSession, didBecomeInvalidWithError error: Error?) {
            guard let error = error else { return }
            hedgeLog("[Network] did become invalid with error \(error)")
            client?.urlProtocol(self, didFailWithError: error)
        }

        public func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            hedgeLog("[Network] did receive authentication challenge \(challenge)")
            let wrappedChallenge = URLAuthenticationChallenge(
                authenticationChallenge: challenge,
                sender: PostHogAuthenticationChallengeSender(handler: completionHandler)
            )
            client?.urlProtocol(self, didReceive: wrappedChallenge)
        }

        public func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    final class PostHogAuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {
        typealias AuthenticationChallengeCompletionHandler = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        let handler: AuthenticationChallengeCompletionHandler

        init(handler: @escaping AuthenticationChallengeCompletionHandler) {
            self.handler = handler
            super.init()
        }

        func use(_ credential: URLCredential, for _: URLAuthenticationChallenge) {
            handler(.useCredential, credential)
        }

        func continueWithoutCredential(for _: URLAuthenticationChallenge) {
            handler(.useCredential, nil)
        }

        func cancel(_: URLAuthenticationChallenge) {
            handler(.cancelAuthenticationChallenge, nil)
        }

        func performDefaultHandling(for _: URLAuthenticationChallenge) {
            handler(.performDefaultHandling, nil)
        }

        func rejectProtectionSpaceAndContinue(with _: URLAuthenticationChallenge) {
            handler(.rejectProtectionSpace, nil)
        }
    }

    extension URLRequest {
        var asMutableURLRequest: NSMutableURLRequest {
            ((self as NSURLRequest).mutableCopy() as? NSMutableURLRequest)!
        }
    }

#endif
