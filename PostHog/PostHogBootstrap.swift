//
//  PostHogBootstrap.swift
//  PostHog
//

import Foundation

/// Pre-seeded values applied on the very first SDK launch when no per-device state has
/// been persisted yet.
///
/// Set ``PostHogConfig/bootstrap`` before calling `setup(_:)` to ensure events captured
/// synchronously during initialization (`Application Installed` / `Application Updated`,
/// pre-identify lifecycle events) carry a caller-controlled `$distinct_id` rather than
/// the SDK-generated UUID. Mirrors the [`bootstrap` option in `posthog-js`](https://posthog.com/docs/feature-flags/bootstrapping).
///
/// Bootstrap only seeds the very first session. Once an anonymous ID is persisted on
/// disk, or `identify(...)` has been called, the bootstrap values are ignored — they
/// never override an already-identified user or re-link traffic across a previous
/// anon→identified merge.
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

    @objc public override init() {
        super.init()
    }

    @objc public init(distinctID: String?, isIdentifiedID: Bool = false) {
        self.distinctID = distinctID
        self.isIdentifiedID = isIdentifiedID
        super.init()
    }
}
