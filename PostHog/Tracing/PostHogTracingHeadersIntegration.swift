#if os(iOS)
    import Foundation

    private enum PostHogTracingHeaders {
        static let distinctId = "X-POSTHOG-DISTINCT-ID"
        static let sessionId = "X-POSTHOG-SESSION-ID"

        static func addingHeaders(
            to request: URLRequest,
            hostnames: Set<String>,
            distinctId: String,
            sessionId: String?
        ) -> URLRequest {
            guard shouldAddHeaders(to: request.url, hostnames: hostnames) else {
                return request
            }

            var request = request

            if let sessionId, !sessionId.isEmpty {
                request.setValue(sessionId, forHTTPHeaderField: Self.sessionId)
            }

            if !distinctId.isEmpty {
                request.setValue(distinctId, forHTTPHeaderField: Self.distinctId)
            }

            return request
        }

        static func normalizeHostnames(_ hostnames: [String]) -> Set<String> {
            Set(
                hostnames
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        }

        private static func shouldAddHeaders(to url: URL?, hostnames: Set<String>) -> Bool {
            guard let requestHost = url?.host?.lowercased(), !hostnames.isEmpty else {
                return false
            }

            return hostnames.contains(requestHost)
        }
    }

    final class PostHogTracingHeadersIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static let integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private weak var postHog: PostHogSDK?
        private var registrationId: UUID?
        private let normalizedHostnamesLock = NSLock()
        private var cachedHostnames: [String] = []
        private var normalizedHostnames = Set<String>()

        func install(_ postHog: PostHogSDK) throws {
            try Self.integrationInstalledLock.withLock {
                if Self.integrationInstalled {
                    throw InternalPostHogError(description: "Tracing headers integration already installed to another PostHogSDK instance.")
                }
                Self.integrationInstalled = true
            }

            self.postHog = postHog

            do {
                try startInstrumentation()
            } catch {
                Self.integrationInstalledLock.withLock {
                    Self.integrationInstalled = false
                }
                self.postHog = nil
                throw error
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            if self.postHog === postHog || self.postHog == nil {
                stop()
                self.postHog = nil
                Self.integrationInstalledLock.withLock {
                    Self.integrationInstalled = false
                }
            }
        }

        func start() {
            do {
                try startInstrumentation()
            } catch {
                hedgeLog("Tracing headers integration failed to start: \(error)")
            }
        }

        func stop() {
            guard let registrationId else {
                return
            }

            URLSessionInstrumentation.shared.unregister(registrationId)
            self.registrationId = nil
        }

        private func startInstrumentation() throws {
            guard registrationId == nil else {
                return
            }

            registrationId = try URLSessionInstrumentation.shared.register(requestModifier: { [weak self] request in
                self?.addTracingHeaders(to: request) ?? request
            })
        }

        private func addTracingHeaders(to request: URLRequest) -> URLRequest {
            guard let postHog else {
                return request
            }

            return PostHogTracingHeaders.addingHeaders(
                to: request,
                hostnames: getNormalizedHostnames(for: postHog),
                distinctId: postHog.getDistinctId(),
                sessionId: postHog.sessionManager.getSessionId(readOnly: true)
            )
        }

        private func getNormalizedHostnames(for postHog: PostHogSDK) -> Set<String> {
            let hostnames = postHog.config.addTracingHeaders ?? []

            return normalizedHostnamesLock.withLock {
                if hostnames != cachedHostnames {
                    cachedHostnames = hostnames
                    normalizedHostnames = PostHogTracingHeaders.normalizeHostnames(hostnames)
                }

                return normalizedHostnames
            }
        }
    }

    #if TESTING
        extension PostHogTracingHeadersIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
            }
        }
    #endif
#endif
