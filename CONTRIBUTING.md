# Contributing

If you would like to contribute code to `posthog-ios` you can do so through GitHub by forking the repository and opening a pull request against `main`.

## Development guide

1. Install Xcode.
2. Run `make bootstrap` to install the required development tools.
3. Use the same core checks that CI runs before opening a pull request:

```bash
make lint
make test
make buildSdk
```

- `make lint` runs the formatting and lint checks used in CI.
- `make test` runs the SDK test suite.
- `make buildSdk` verifies the SDK builds across supported platforms.

If you prefer to work in Xcode, open `PostHog.xcodeproj`.

When submitting code, please make every effort to follow existing conventions and style in order to keep the code as readable as possible. Please also consider adding unit tests covering your change, as this makes your change much more likely to be accepted.

Above all, thank you for contributing!
