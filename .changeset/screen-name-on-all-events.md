---
"posthog-ios": minor
---

Auto-attach `$screen_name` to every captured event after `PostHogSDK.shared.screen()` has been called (manually or via screen-view auto-capture). Cached value is cleared by `reset()` and `close()`. Closes posthog-android#119.

**To opt out of `$screen_name` stamping entirely**, set `PostHogConfig.captureScreenViews = false` **and** stop calling `screen()` manually. Disabling `captureScreenViews` alone is not sufficient — a single manual `screen("Home")` call will re-enable stamping.

## Behavior changes

These all affect what your events carry on the wire. Review your dashboards/insights/HogQL queries:

- **Cross-event stamping.** `$exception`, `$identify`, `$autocapture`, `$create_alias`, `$groupidentify`, custom events, etc. will start carrying `$screen_name` whenever a screen has been recorded in the session. Previously only `$screen` events carried it. `$snapshot` events are excluded.
- **SwiftUI `$screen` event payloads change shape.** Names are now sanitized: `$screen_name = "UIHostingController<MyView>"` → `$screen_name = "MyView"`. **Hard cutover for HogQL filters** like `properties.$screen_name LIKE 'UIHostingController%'` or `properties.$screen_name LIKE 'ModifiedContent%'` — they will start returning zero matches. Customers will need to rewrite those filters using the bare type name.
- **Type-erased SwiftUI roots stop emitting `$screen`.** Apps whose `body: some View` resolves to `AnyView` (e.g. mixed-type branches returning `AnyView(...)`) will see `$screen` event counts **drop to zero** for those screens — the swizzle still fires, but sanitize returns nil and the event is suppressed. To restore: expose a real type via `.postHogScreenView("MyScreen")` modifier, or call `screen("MyScreen")` manually.
- **`$screen` event override semantics flipped.** `screen("Home", properties: ["$screen_name": "Override"])` now ships `$screen_name = "Override"` on the `$screen` event. Previously the `screenTitle` arg won (`{ prop, _ in prop }`). This aligns iOS with Android. Customers who passed `$screen_name` defensively in `properties` will see their override take effect.
- **`screen("")` is silently dropped.** Previously an empty `screenTitle` emitted a `$screen` event with `$screen_name = ""`; now nothing is emitted and the cache is untouched. Customers using empty-string as a sentinel in dashboards will see those rows disappear.
- **`screen("AnyView")` (literal manual call) is honored.** Only `AnyView` that surfaced from stripping `UIHostingController<...>` / `ModifiedContent<...>` wrappers is dropped (auto-capture noise from `body: some View` type erasure). A caller who literally typed `screen("AnyView")` gets that event through.

## Known asymmetry

Live `captureException(_:)` calls (caught and rethrown by your code) **will** carry `$screen_name`. Crash-replay `$exception` events fired from the error-tracking auto-capture integration (out-of-process crashes) **will not** — that path bypasses `buildProperties` via `skipBuildProperties: true` to preserve the snapshot taken at crash time. If you segment exception analytics by `$screen_name`, expect a gap on the crash-replay rows.
