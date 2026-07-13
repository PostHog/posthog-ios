//
//  PostHogBootstrap.swift
//  PostHog
//

import Foundation

/// Pre-seeded values applied on the very first SDK launch when no per-device state has
/// been persisted yet.
///
/// Set ``PostHogConfig/bootstrap`` before calling `setup(_:)` to seed identity and feature
/// flag state before any network request completes. This ensures events captured
/// synchronously during initialization (`Application Installed` / `Application Updated`,
/// pre-identify lifecycle events) carry a caller-controlled `$distinct_id` rather than the
/// SDK-generated UUID, and that feature flag reads return caller-provided values before the
/// first `/flags` response. Mirrors the [`bootstrap` option in `posthog-js`](https://posthog.com/docs/feature-flags/bootstrapping).
///
/// Bootstrap only seeds the very first session. Once an anonymous ID is persisted on
/// disk, or `identify(...)` has been called, the bootstrap identity is ignored — it
/// never overrides an already-identified user or re-links traffic across a previous
/// anon→identified merge. Bootstrapped feature flags form a base layer only: values from
/// `/flags` overlay them for overlapping keys, while bootstrapped-only keys remain
/// available.
@objc(PostHogBootstrap) public class PostHogBootstrap: NSObject {
    /// The distinct ID to seed on first launch.
    ///
    /// When ``isIdentifiedID`` is `false` (the default), this becomes the anonymous ID —
    /// the `$distinct_id` on pre-identify events. When `true`, it is treated as an
    /// already-identified user's distinct ID and the SDK skips the `$identify` merge
    /// for it.
    @objc public var distinctID: String?

    /// Whether ``distinctID`` represents an already-identified user.
    ///
    /// Defaults to `false`. Set to `true` when the host application has resolved the
    /// user's identity outside the SDK (for example from a backend session token) and
    /// wants the iOS SDK to treat them as identified from the first event onward.
    @objc public var isIdentifiedID: Bool = false

    /// Feature flag values served until the first `/flags` response arrives.
    ///
    /// Maps a flag key to its value (a `Bool` for boolean flags or a `String` for
    /// multivariate flags). These values are served immediately after setup so flag reads
    /// don't fall back to not-loaded defaults during cold start. Loaded values overlay
    /// bootstrapped ones for overlapping keys; bootstrapped-only keys survive a load.
    @objc public var featureFlags: [String: Any]?

    /// JSON payloads paired with ``featureFlags``, keyed by flag key.
    ///
    /// Each value is the already-decoded payload (for example a dictionary, array, string,
    /// or number) for the matching flag, served alongside ``featureFlags`` before the first
    /// `/flags` response.
    @objc public var featureFlagPayloads: [String: Any]?

    @objc override public init() {
        super.init()
    }

    @objc public convenience init(
        distinctID: String? = nil,
        isIdentifiedID: Bool = false,
        featureFlags: [String: Any]? = nil,
        featureFlagPayloads: [String: Any]? = nil
    ) {
        self.init()
        self.distinctID = distinctID
        self.isIdentifiedID = isIdentifiedID
        self.featureFlags = featureFlags
        self.featureFlagPayloads = featureFlagPayloads
    }
}
