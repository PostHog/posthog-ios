# PostHog iOS SDK Compliance Adapter

This adapter wraps the PostHog iOS SDK for compliance testing with the PostHog SDK Test Harness.

## Architecture: Hybrid Runner

**Why not Docker?** The iOS SDK requires Darwin-specific frameworks (`SystemConfiguration`, UIKit, etc.) that don't exist on Linux. Docker only supports Linux containers, so we use a **hybrid architecture**:

- **Adapter**: Runs **natively on macOS** (using Swift/Vapor)
- **Test Harness**: Runs in **Docker** (Linux container)
- **Mock Server**: Runs in **Docker** (Linux container)

The test harness connects to the adapter via `host.docker.internal`, allowing Docker containers to communicate with the macOS host.

### Components

- **Language**: Swift with Vapor web framework
- **HTTP Interception**: Custom URLProtocol subclass (`RequestInterceptor`)
- **SDK Integration**: Native integration using Swift Package Manager
- **Deployment**: macOS runners (GitHub Actions `macos-latest` or local Mac)

## How It Works

### Request Interception

The adapter uses **URLSessionConfiguration injection** to intercept HTTP requests:

1. Adapter creates a custom `URLSessionConfiguration` with `RequestInterceptor` in `protocolClasses`
2. Injects it into `PostHogConfig.urlSessionConfiguration` (new property added to SDK)
3. SDK's `PostHogApi.sessionConfig()` uses the injected configuration
4. All SDK network requests go through our `RequestInterceptor` URLProtocol subclass
5. Interceptor tracks status codes and retry attempts

### Key Features

- **URLSessionConfiguration injection**: Custom property added to PostHogConfig for testability
- **Fast flushing**: Configures SDK with `flushAt: 1` and minimal flush interval
- **Feature disabling**: Turns off surveys, session replay, autocapture, etc.
- **TESTING flag**: Builds with `-Xswiftc -DTESTING` to handle command-line environment
- **Host rewriting**: Converts `host.docker.internal` to `localhost` for hybrid networking

## API Endpoints

### GET /health

Returns SDK information:

```json
{
  "sdk_name": "posthog-ios",
  "sdk_version": "3.0.0",
  "adapter_version": "1.0.0"
}
```

### POST /init

Initialize the SDK with configuration:

```json
{
  "api_key": "phc_test",
  "host": "http://mock-server:8000",
  "flush_at": 1,
  "flush_interval_ms": 100
}
```

### POST /capture

Capture a single event:

```json
{
  "event": "test_event",
  "distinct_id": "user_123",
  "properties": {
    "key": "value"
  }
}
```

### POST /flush

Force flush all pending events. **Critical**: This endpoint waits 2 seconds for the async network requests to complete.

### GET /state

Returns internal state for test assertions:

```json
{
  "total_events_sent": 5,
  "requests_made": [
    {
      "timestamp_ms": 1234567890,
      "status_code": 200,
      "retry_attempt": 0,
      "event_count": 3,
      "uuid_list": ["uuid1", "uuid2", "uuid3"]
    }
  ]
}
```

### POST /reset

Reset the SDK and adapter state.

## Running Tests

### Prerequisites

1. **macOS environment** (local Mac or GitHub Actions `macos-latest`)
2. **Docker Desktop** installed and running
3. **Swift 5.9+** installed

### Steps

1. **Build the test harness image**:

```bash
cd ~/work/posthog-sdk-test-harness
docker build -t posthog-sdk-test-harness:debug .
```

2. **Start the adapter on macOS** (in one terminal):

```bash
cd ~/work/posthog-ios/sdk_compliance_adapter
swift run
```

The adapter will start on `http://localhost:8080`

3. **Run the tests** (in another terminal):

```bash
cd ~/work/posthog-ios/sdk_compliance_adapter
docker-compose up --abort-on-container-exit
```

The test harness will:
- Start the mock server in Docker
- Connect to the adapter via `host.docker.internal:8080`
- Run compliance tests
- Report results

### Quick Test Script

Or use the convenience script:

```bash
cd ~/work/posthog-ios/sdk_compliance_adapter
./run_tests.sh
```

## Implementation Notes

### SDK Enhancement: URLSessionConfiguration Injection

**Problem**: The SDK creates its own URLSession instances internally, ignoring globally registered URLProtocols.

**Solution**: Added a new property to `PostHogConfig`:

```swift
// PostHogConfig.swift (new property)
@objc public var urlSessionConfiguration: URLSessionConfiguration?
```

Modified `PostHogApi.sessionConfig()` to use it:

```swift
// PostHogApi.swift
func sessionConfig() -> URLSessionConfiguration {
    let config = self.config.urlSessionConfiguration ?? URLSessionConfiguration.default
    // ... configure headers
}
```

**Benefits**:
- Enables HTTP interception for testing
- Useful for proxies, SSL pinning, custom networking
- Backward compatible (nil = default behavior)
- Clean dependency injection pattern

### Why URLProtocol?

URLProtocol is the standard way to intercept HTTP requests:
- Native iOS/macOS API
- Works with all URLSession-based networking
- Can inspect and modify requests/responses
- No global state pollution

### Gzip Handling

The iOS SDK gzips request bodies. Our interceptor includes the same `gunzipped()` implementation from the SDK's `Data+Gzip.swift` for decompression.

### Flush Timing

The `/flush` endpoint is critical for tests. It must:
1. Call `sdk.flush()` to trigger event sending
2. Wait for the async network request to complete (2 seconds)
3. Allow the mock server to process the request

Without the wait, tests will fail because they check state before events are sent.

### SDK Configuration

The adapter configures the SDK for fast, predictable testing:

```swift
config.flushAt = 1  // Send after 1 event
config.flushIntervalSeconds = 0.1  // 100ms timer
config.captureApplicationLifecycleEvents = false
config.captureScreenViews = false
config.preloadFeatureFlags = false
config.sessionReplay = false
config.surveys = false

// Inject custom URLSession configuration for interception
let sessionConfig = URLSessionConfiguration.default
sessionConfig.protocolClasses = [RequestInterceptor.self]
config.urlSessionConfiguration = sessionConfig
```

### Host Rewriting

Since the adapter runs on the macOS host (not in Docker), it needs to access the mock server via `localhost`, not `host.docker.internal`:

```swift
// Rewrite host.docker.internal → localhost
let host = initReq.host.replacingOccurrences(
    of: "host.docker.internal",
    with: "localhost"
)
```

## Test Results

**Current: 11/17 tests passing (65%)**

### ✅ Passing (11)

- All format validation tests (5/5)
- UUID generation and deduplication (1/2)
- Compression and batch format (2/2)
- Error handling for 400, 401, 413 (3/5)

### ❌ Failing (6)

**Retry behavior** (5 tests):
- SDK does not retry on 503, 408 errors
- SDK does not implement backoff
- SDK does not respect Retry-After header

**Note**: These failures reflect actual iOS SDK behavior (no retry logic implemented). This may be intentional.

## Troubleshooting

### Build Failures

If Swift Package Manager fails to resolve dependencies:

```bash
cd ~/work/posthog-ios/sdk_compliance_adapter
swift package reset
swift package resolve
```

### Network Issues

If requests aren't being intercepted:
- Verify `config.urlSessionConfiguration` is set with RequestInterceptor
- Check that host rewriting is working (`host.docker.internal` → `localhost`)
- Check logs for `[INTERCEPTOR]` messages
- Ensure mock server port 8081 is accessible from adapter

### Timing Issues

If tests fail due to timing:
- Increase wait time in `/flush` endpoint (currently 2 seconds)
- Check mock server logs for request timing
- Verify SDK flush configuration

## CI/CD Integration

A GitHub Actions workflow is available at `.github/workflows/sdk-compliance.yml`. It runs on `macos-14` runners using the hybrid architecture.

## References

- Test harness: https://github.com/PostHog/posthog-sdk-test-harness
