# Vendored Dependency Upstreams

This file records the upstream sources and commit hashes used to pull vendored dependencies in `vendor/`.

## Dependencies

| Dependency | Local path | Upstream repository | Ref | Commit SHA | Confidence |
| --- | --- | --- | --- | --- | --- |
| PLCrashReporter | `vendor/PHPLCrashReporter` | https://github.com/microsoft/plcrashreporter | `1.12.2` | `0254f941c646b1ed17b243654723d0f071e990d0` | Verified |
| protobuf-c | `vendor/PHPLCrashReporter/Source` (relocated — see notes) | https://github.com/protobuf-c/protobuf-c | `1.4.0` | — | Verified (from `PROTOBUF_C_VERSION` in `protobuf-c.h`) |
| libwebp | `vendor/libwebp` | https://github.com/webmproject/libwebp | `v1.5.0` | `a4d7a715337ded4451fec90ff8ce79728e04126c` | Inferred |

## Notes

- `PHPLCrashReporter` commit is verified against upstream history. The vendored copy includes local compiler-warning cleanup for explicit integer conversions in PLCrashReporter/protobuf-c sources.
- **protobuf-c is bundled inside PLCrashReporter upstream at `Dependencies/protobuf-c/protobuf-c/`. In this vendored copy, `protobuf-c.{h,c}` are relocated into `Source/`, next to the only file that includes them across directories (`PLCrashReport.pb-c.h` → `#include "protobuf-c.h"`).** This makes that include resolve via the compiler's same-directory rule instead of a `HEADER_SEARCH_PATHS` entry, so it no longer breaks when a consumer's build drops the search path (see issue #469). Trade-off: the local layout no longer mirrors upstream's `Dependencies/protobuf-c/` — when re-vendoring, re-apply this move (it is done manually today; automate if re-vendoring becomes recurring).
- `libwebp` commit is inferred from the vendored code ABI surface and import timing.
- `libwebp` was slimmed down after vendoring to remove unused components (for example, animated image support paths) and keep the SDK footprint smaller.
- Both vendored dependencies include local PostHog-prefixed/private integration changes after import, including assertion contracts that are made explicit for Clang static analyzer runs.
