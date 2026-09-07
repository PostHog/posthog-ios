# PostHog iOS SDK compliance adapter

This profile exercises the local `PostHogSDK.shared` Swift package on **macOS**, using
Vapor to expose the harness API. It is shared-core coverage, not iOS simulator/device,
UIKit, replay, Linux, or an Apple-platform matrix result. CI uses `macos-15-intel` and
the harness 1.0.0 Docker image (contract 1.2).

## Coverage and configuration

- `capture_v0`, `/batch`, SDK-default gzip: **30 capture tests**.
  `--sdk-type server` describes the batch wire format, not a server-side product.
- **17 feature flag tests**, with no filters or expected-failure suppression.
- No analytics V1, dedicated AI capture, or alternative codec profile is advertised.
- Lifecycle capture, screen capture, swizzling, and flag preload are disabled to isolate
  explicit test actions. Thus init/capture lifecycle passes do not test native defaults.
- `flush_at`, `flush_interval_ms`, and capture `max_retries` map to existing public config.
  Default flush interval is 500ms (5s when batching is requested). Compression remains
  the SDK default; there is no compression-off control in this profile.
- The existing `TESTING` build flag permits command-line bundle identity fallback.
  Storage is isolated under an adapter-owned temporary home and cleared between tests.

## Public API mapping

`/capture` parses an optional ISO-8601 timestamp into `Date` and passes it to the
existing `capture(..., timestamp:)` overload. Invalid timestamps return HTTP 400.
Custom properties are not normalized. A passive `setBeforeSend` hook returns events
unchanged and observes the **SDK-generated** UUID for the capture response.

`/get_feature_flag` sets person/group properties with reload disabled, calls public
`identify` and `group`, awaits `reloadFeatureFlags`' callback, then reads the public
cached `getFeatureFlag` value. Missing values remain JSON null. The SDK owns flags HTTP,
response parsing, 502/504 retries, and its default `$feature_flag_called` event.
There is no flags HTTP client or manual called-event capture in the adapter.

Identity/group operations themselves can reload flags and emit events. These are
retained, so a flag action is **not guaranteed to send exactly one request**. For
`force_remote: false`, the explicit reload is omitted; identity/group changes can
still cause their normal reloads. Identified-user switching requires a fresh `/init`.
Groups use the mobile SDK's additive association semantics, not per-call replacement.

### Known flags contract differences

Several assertions describe a stateless server client rather than this mobile API:

- Exact request counts include identify/group-triggered reloads as well as the explicit
  reload. This affects three wire tests, the compound person test, remote-call counting,
  and the two retry tests, even when native wire/retry behavior is exercised correctly.
- Group assertions inspect the **first** request, which can precede group association;
  subsequent reloads contain the configured groups.
- Empty `group_properties` and `geoip_disable` are omitted by the SDK. There is no
  per-call GeoIP or singleton `flag_keys_to_evaluate` argument to forward.
- One-shot response fixtures can be consumed by the identity-triggered reload or its
  analytics event before the explicit reload. Value/called-event assertions can therefore
  see the default mock response instead of the configured flag value.
- Default preload and ordinary cached-getter network behavior are not established by
  this configured profile.

These tests remain selected and their genuine failures remain visible in reports.

## Flush and state observation

The injected public `urlSessionConfiguration` uses a URLProtocol to forward analytics
uploads unchanged, recording wire UUIDs and HTTP acknowledgments. Flags use the SDK's
session directly. `/state` reports captured/sent UUID counts, repeated wire attempts,
requests, and outstanding observations; it does not read the SDK's private queue.

`/flush` calls SDK `flush()` **once**, then waits up to 25 seconds for all observed
captures to receive a success or known terminal batch response. It does not implement
retries, shorten backoff, or treat network idleness as delivery. Submitted captures
not observed by the hook remain outstanding. Multi-event 413 responses remain pending
because the SDK can split them. `events_flushed` counts new successful acknowledgments
during that call, not cumulative deliveries.

There is no public native queue-drain callback. Transient failures cannot be declared
dropped merely because the configured retry budget appears exhausted. Unresolved
observations return **HTTP 504**, including the harness `max_retries_respected` case
and retry timers longer than the observation deadline. This is a conservative adapter
completion limitation, not evidence of failed SDK retry limits. `/reset` closes the SDK
and replaces the observer; late callbacks cannot update the next test's observer.

## Running

On macOS with Xcode (Swift 6+ for the adapter's Swift Testing tests) and Docker/Colima available:

```sh
cd sdk_compliance_adapter
make build
make test
make smoke ADAPTER_PORT=8082 MOCK_PORT=8083
./run_tests.sh
```

To build without Docker, run `make build` and start
`.build/debug/PostHogIOSComplianceAdapter serve --hostname 0.0.0.0 --port 8080`.
The pinned harness can then connect to it. Local native harness execution against the
same contract is also possible; record its exact source ref and host architecture.

The smoke tests use endpoint-specific flags fixtures that remain available across
identity/group reloads. They separately verify native 502/504 retry, returned variants,
group context and SDK called-events; they are not substituted harness results.

`make format` and `make lint` in this directory scope checks to the adapter.
`SCRATCH_PATH=/path/to/build` can isolate Swift build artifacts.

CI runs all **47** selected cases and uploads a runtime-named report and adapter logs.
Assertion failures remain advisory. Missing/empty/incomplete report inventory is a
separate setup failure, verified by `verify_report.py`. Read the actual report, not
only the advisory job status, when assessing coverage.
