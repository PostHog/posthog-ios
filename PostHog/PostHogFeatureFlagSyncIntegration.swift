import Foundation

/// Integration that synchronizes feature flag reloading with successful event delivery
/// Solves the issue where feature flags are reloaded before identity events are actually sent to the API
class PostHogFeatureFlagSyncIntegration: PostHogIntegration {
    private weak var postHog: PostHogSDK?
    private var observer: NSObjectProtocol?

    /// Events that should trigger feature flag reloading when successfully sent
    /// Note: $groupidentify is excluded because groups are updated locally first,
    /// triggering an immediate reload, then the event is sent for server sync
    private let identityChangingEvents: Set<String> = [
        "$identify",
        "$create_alias",
    ]

    init() {
        // Empty init - installation happens via install() method
    }

    deinit {
        stop()
    }

    // MARK: - PostHogIntegration Protocol

    func install(_ postHog: PostHogSDK) throws {
        guard self.postHog == nil else {
            throw InternalPostHogError(description: "Feature flag sync integration already installed to another PostHogSDK instance.")
        }

        self.postHog = postHog
        start()
    }

    func uninstall(_: PostHogSDK) {
        stop()
        postHog = nil
    }

    func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: PostHogSDK.didSendEvents,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleEventsSent(notification)
        }
    }

    func stop() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleEventsSent(_ notification: Notification) {
        guard let postHog = postHog else { return }

        // Don't reload if remoteConfig is nil (feature flags not available)
        guard let remoteConfig = postHog.remoteConfig else {
            return
        }

        guard let events = notification.userInfo?["events"] as? [PostHogEvent] else {
            return
        }

        // Check if any of the sent events are identity-changing events
        let hasIdentityChangingEvent = events.contains { event in
            identityChangingEvents.contains(event.event)
        }

        if hasIdentityChangingEvent {
            remoteConfig.reloadFeatureFlags()
        }
    }
}
