# Vendored Dependency Upstreams

This file records the upstream sources and commit hashes used to pull vendored dependencies in `vendor/`.

## Dependencies

| Dependency | Local path | Upstream repository | Ref | Commit SHA | Confidence |
| --- | --- | --- | --- | --- | --- |
| PLCrashReporter | `vendor/PHPLCrashReporter` | https://github.com/microsoft/plcrashreporter | `1.12.2` | `0254f941c646b1ed17b243654723d0f071e990d0` | Verified |
| libwebp | `vendor/libwebp` | https://github.com/webmproject/libwebp | `v1.5.0` | `a4d7a715337ded4451fec90ff8ce79728e04126c` | Inferred |

## Notes

- `PHPLCrashReporter` commit is verified against upstream history.
- `libwebp` commit is inferred from the vendored code ABI surface and import timing.
- `libwebp` was slimmed down after vendoring to remove unused components (for example, animated image support paths) and keep the SDK footprint smaller.
- Both vendored dependencies include local PostHog-prefixed/private integration changes after import.
