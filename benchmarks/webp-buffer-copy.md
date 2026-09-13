# WebP output-buffer ownership experiment

## Verdict

A small allocation optimization, not a meaningful encoding-speed improvement or an Android-style OOM fix. The prototype removes one compressed-payload allocation/copy. It leaves screenshot rendering, vImage pixel conversion, libwebp's working buffers, and Base64 output allocation unchanged.

The largest tested compressed payload showed a repeatable ~0.52 MB reduction in XCTest's **whole-process peak physical memory**. Smaller cases differed by only ~0.08–0.11 MB, close to between-run variation. These are observed process metrics, not exact per-frame allocation savings; allocator caching and test-runner state affect them. Do not extrapolate them to device OOM prevention.

Recommendation: reasonable as a small, low-priority allocation cleanup, but not justified as a speedup. Profile raw-pixel/rendering allocations on a physical device before pursuing substantial replay memory improvements.

## Change

Baseline: `2a40ee24aebdb4d77525c5f547b61692c8ef87a9`, with the same benchmark and ownership tests added.

Candidate: replace `Data(bytes: writer.mem, count: writer.size)` with ownership transfer through `Data(bytesNoCopy:count:deallocator:)`. Reset the WebP writer before its deferred cleanup, and release the transferred buffer with `PHWebPFree` when Data is destroyed. Failure paths retain the original cleanup.

The eliminated copy is proportional to compressed payload size, **not** raw frame size. No-copy Data also retains the writer's spare capacity until Data is released, rather than keeping an exact-size copy. Consequently, it does not guarantee lower memory at every stage of the pipeline or for long-lived Data.

## Method

- Apple M4 Pro, 14 CPU cores, 48 GB RAM; macOS 26.6.2; Xcode 26.6.
- iPhone 17 Pro simulator, iOS 26.4, arm64; Release optimization, testability enabled.
- No sanitizers during performance measurements; parallel testing disabled.
- Four preloaded images: synthetic opaque UI blocks, two existing photographic fixtures, and an alpha fixture.
- Measure `UIImage.toBase64`: pixel conversion + WebP compression + Data handoff + Base64/data-URL construction and equality assertion. Image loading/rendering is outside measurement. This is **not** a full replay capture benchmark.
- Five explicit warm-up encodes; 20 measured iterations per case per process invocation.
- Three invocations per version, 60 measured samples per case/version. Order: baseline-2, candidate-1, candidate-2, baseline-3, baseline-4, candidate-3.
- XCTest clock and physical-memory metrics. Table aggregates equally sized runs. Per-run means and ranges are in `webp-buffer-copy.csv`.
- `baseline-1` was a build-only failure caused by overriding inherited Swift compilation conditions; the benchmark target was corrected before collecting any measurements.

## Results

| Image | Pixels | Compressed bytes | Baseline time | No-copy time | Time change | Baseline process peak | No-copy process peak |
|---|---|---:|---:|---:|---:|---:|---:|
| Synthetic UI, q30 | 390 × 844 | 2,380 | 8.246 ms | 8.189 ms | −0.69% | 40.802 MB | 40.720 MB |
| Photo, q30 | 1024 × 752 | 36,332 | 35.322 ms | 35.490 ms | +0.48% | 43.218 MB | 43.111 MB |
| Photo, q80 | 1024 × 772 | 226,958 | 59.193 ms | 58.860 ms | −0.56% | 46.154 MB | 45.634 MB |
| Alpha, q80 | 400 × 301 | 12,286 | 9.434 ms | 9.311 ms | −1.30% | 34.112 MB | 34.031 MB |

MB is decimal. Timing differences are small relative to between-run variation and do not establish a useful speedup. The q80 photograph is intentionally above replay's default quality (q30).

## Reproduce

In this worktree:

```sh
make benchmarkWebP \
  WEBP_BENCHMARK_DESTINATION='platform=iOS Simulator,id=0E96EAC6-732E-41CA-8BF8-B35CF1C40F53' \
  WEBP_BENCHMARK_EXTRA_ARGS='-resultBundlePath /tmp/webp-candidate.xcresult'
```

Choose an available simulator identifier on another machine. Result bundle paths must not already exist. Run three times per implementation with unique paths, keeping the device and build options fixed. To measure the baseline, use the baseline version of **only** `PostHog/Utils/UIImage+WebP.swift`, retaining the benchmark/tests/Makefile; then restore the candidate. No production benchmark switch is needed.

For ownership validation under Address Sanitizer:

```sh
make benchmarkWebP \
  WEBP_BENCHMARK_DESTINATION='platform=iOS Simulator,id=0E96EAC6-732E-41CA-8BF8-B35CF1C40F53' \
  WEBP_BENCHMARK_EXTRA_ARGS='-enableAddressSanitizer YES -skip-testing:PostHogTests/PostHogWebPBenchmark'
```

Original logs, result bundles, and full metric samples are locally available at `/tmp/ios-webp-benchmark/` (`measurements.json`, `baseline-{2,3,4}.log`, `candidate-{1,2,3}.log`, and matching `.xcresult` bundles).

## Validation

- All six benchmark invocations passed: four performance cases, three existing golden-byte tests, and three parameterized ownership cases.
- Ownership tests cover data surviving encoder cleanup and autorelease-pool drainage, subsequent encode/free churn, Base64 round-trip and exact data-URL compatibility, and copy-on-write mutation isolation.
- Targeted correctness tests also passed with Address Sanitizer enabled. No physical-device profiling or leak-instrument run was performed.
- `make test`: passed (172 XCTest tests and 799 Swift Testing tests on macOS; iOS-only paths covered by the simulator runs above).
- `make format`: passed, no formatting changes required.
- `make lint`: passed with 28 existing SDK warnings, zero serious violations.
- `make build`: SDK builds passed for iOS, macOS, Mac Catalyst, tvOS, watchOS, and visionOS; platform examples and XCFramework archives passed. The external SDK client then failed package resolution because its manifest expects package identity `posthog-ios`, while this worktree's folder identity is `posthog-ios-investigate-android-755`. CocoaPods example stages were not reached. No unrelated build configuration was changed.
