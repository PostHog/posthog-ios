---
"posthog-ios": patch
---

fix: make vendored protobuf-c header resolution robust against header-search-path loss

Relocate the vendored `protobuf-c.{h,c}` next to `PLCrashReport.pb-c.h`, the only
source that includes `protobuf-c.h` across directories, so the include resolves via
the compiler's same-directory rule instead of a `HEADER_SEARCH_PATHS` entry. This
prevents intermittent `'protobuf-c.h' file not found` build failures when a
consumer's build drops the pod's header search paths.
