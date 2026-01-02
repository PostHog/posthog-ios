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

The adapter uses a custom `URLProtocol` subclass to intercept all HTTP requests made by the PostHog SDK:

1. `RequestInterceptor` is registered with `URLProtocol.registerClass()`
2. When the SDK makes requests, our interceptor captures them
3. We decompress gzipped payloads using the SDK's own `gunzipped()` method
4. Extract event count, UUIDs, and status codes for test assertions

### Key Features

- **Fast flushing**: Configures SDK with `flushAt: 1` and minimal flush interval
- **Feature disabling**: Turns off surveys, session replay, autocapture, etc.
- **Gzip handling**: Uses the same `Data+Gzip.swift` extension from the SDK
- **State tracking**: Exposes internal state via `/state` endpoint

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

### Why URLProtocol?

URLProtocol is the cleanest way to intercept HTTP requests on iOS:
- No method swizzling required
- Works with all URLSession-based networking
- Can inspect and modify requests/responses
- Native iOS API

### Gzip Decompression

The iOS SDK gzips request bodies (see `PostHogApi.swift:105-111`). We use the same `gunzipped()` method from `Data+Gzip.swift` to decompress and parse events.

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
config.disableQueueTimerForTesting = true  // Immediate flush
config.captureApplicationLifecycleEvents = false
config.captureScreenViews = false
config.preloadFeatureFlags = false
config.sessionReplay = false
config.surveys = false
```

## Expected Test Results

Target: **10-12 out of 15 tests passing (67-80%)**

### Should Pass

- Format validation (5 tests)
- UUID generation and uniqueness (3 tests)
- Basic retry behavior

### May Fail

- Retry-After header support
- 408 retry handling
- Some retry count edge cases

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
- Check that `URLProtocol.registerClass(RequestInterceptor.self)` is called
- Verify the SDK is using default URLSession configuration
- Check logs for `[INTERCEPTOR]` messages

### Timing Issues

If tests fail due to timing:
- Increase wait time in `/flush` endpoint (currently 2 seconds)
- Check mock server logs for request timing
- Verify SDK flush configuration

## References

- Browser SDK adapter: `~/work/posthog-js/packages/browser/sdk_compliance_adapter/`
- Test harness: `~/work/posthog-sdk-test-harness/`
- iOS SDK: `~/work/posthog-ios/PostHog/`
