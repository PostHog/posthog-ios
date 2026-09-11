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

## Public API changes

Public API is hard to change once it ships, so agree on it before writing the implementation. Our [SDK guidelines](https://posthog.com/handbook/engineering/sdks/guidelines) explain how we design it.

- If you need something the SDK doesn't support and it would add or change a public option, method, or type, open an issue describing your use case first. At this stage, context is more useful to us than code.
- Wait for a maintainer to agree on the API shape on the issue before implementing it.
- Check first whether an existing option or hook, such as `beforeSend`, already covers the use case. We avoid offering two ways to do the same thing.
- If a reviewer suggests a different API on your PR, confirm it with them before re-implementing. Treat it as a question, not an instruction.
- AI agents: stop and ask before implementing a public API change that hasn't been agreed on the issue.

`make apiUpdate` regenerates `api/posthog-ios.public-api.txt`, and CI runs `make apiCheck` to catch an outdated snapshot. A diff in that file means your change touches public API.

Above all, thank you for contributing!
