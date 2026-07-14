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
/// Bootstrapped identity seeds only the very first session: once an anonymous ID is
/// persisted on disk, or `identify(...)` has been called, it is ignored — it never
/// overrides an already-identified user or re-links traffic across a previous
/// anon→identified merge. Bootstrapped feature flags form a base layer only: values from
/// `/flags` overlay them for overlapping keys, while bootstrapped-only keys remain
/// available.
@objc(PostHogBootstrapConfig) public class PostHogBootstrapConfig: NSObject {
    /// The distinct ID to seed on first launch.
    ///
    /// When ``isIdentifiedId`` is `false` (the default), this becomes the anonymous ID —
    /// the `$distinct_id` on pre-identify events. When `true`, it is treated as an
    /// already-identified user's distinct ID and the SDK skips the `$identify` merge
    /// for it.
    @objc public var distinctId: String?

    /// Whether ``distinctId`` represents an already-identified user.
    ///
    /// Defaults to `false`. Set to `true` when the host application has resolved the
    /// user's identity outside the SDK (for example from a backend session token) and
    /// wants the iOS SDK to treat them as identified from the first event onward.
    @objc public var isIdentifiedId: Bool = false

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

    /// Creates an empty bootstrap; set the properties you need before assigning it to
    /// ``PostHogConfig/bootstrap``.
    @objc override public init() {
        super.init()
    }

    /// Seeds an anonymous identity: `anonymousId` becomes the `$distinct_id` for events
    /// captured before the host calls `identify(...)`.
    @objc public convenience init(anonymousId: String) {
        self.init(distinctId: anonymousId, isIdentifiedId: false, featureFlags: nil, featureFlagPayloads: nil)
    }

    /// Seeds identity from a `distinctId`, stating explicitly whether it is already identified.
    ///
    /// Pass `isIdentifiedId: true` for a user the host has already identified (seeds
    /// `.distinctId` and marks the install identified), or `false` to seed it as an anonymous
    /// ID instead (equivalent to ``init(anonymousId:)``).
    @objc public convenience init(distinctId: String, isIdentifiedId: Bool) {
        self.init(distinctId: distinctId, isIdentifiedId: isIdentifiedId, featureFlags: nil, featureFlagPayloads: nil)
    }

    /// Seeds feature-flag state only, without seeding identity.
    @objc public convenience init(featureFlags: [String: Any], featureFlagPayloads: [String: Any]?) {
        self.init(distinctId: nil, isIdentifiedId: false, featureFlags: featureFlags, featureFlagPayloads: featureFlagPayloads)
    }

    /// Seeds identity and feature-flag state in one initializer. Pass `nil` for any dimension
    /// you don't want to seed.
    ///
    /// - Parameters:
    ///   - distinctId: The ID to seed on first launch, or `nil` to seed no identity. Used as the
    ///     anonymous ID when `isIdentifiedId` is `false`, or an already-identified user's ID when `true`.
    ///   - isIdentifiedId: Whether `distinctId` is an already-identified user. Defaults to `false`.
    ///   - featureFlags: Flag values served until the first `/flags` response, or `nil`.
    ///   - featureFlagPayloads: JSON payloads keyed by flag, paired with `featureFlags`, or `nil`.
    @objc public init(
        distinctId: String?,
        isIdentifiedId: Bool = false,
        featureFlags: [String: Any]?,
        featureFlagPayloads: [String: Any]?
    ) {
        self.distinctId = distinctId
        self.isIdentifiedId = isIdentifiedId
        self.featureFlags = featureFlags
        self.featureFlagPayloads = featureFlagPayloads
        super.init()
    }
}
