# Releasing

This repository uses [Changesets](https://github.com/changesets/changesets) for version management and an automated GitHub Actions workflow for releases.

## How to Release

### 1. Add a Changeset

When making changes that should be released, add a changeset:

```bash
pnpm changeset
```

This will prompt you to:
- Select the type of version bump (patch, minor, major)
- Write a summary of the changes

The changeset file will be created in the `.changeset/` directory.

### 2. Create a Pull Request

Create a PR with your changes and the changeset file(s). No release label is required.

### 3. Merge the PR

When the PR is merged to `main`, the release workflow will automatically:

1. Check for changesets
2. Notify the client libraries team in Slack for approval
3. Wait for approval from a maintainer (via GitHub environment protection)
4. Once approved:
   - Apply changesets and bump the version (in `package.json` and `PostHogVersion.swift`)
   - Update the `CHANGELOG.md`
   - Commit the version bump to `main`
   - Create a git tag and GitHub release

Swift Package Manager reads the version from the git tag, so the tag is the release. 4.x is distributed only through Swift Package Manager; see [CocoaPods](#cocoapods).

### Manual Trigger

You can also manually trigger the release workflow from the [Actions tab](https://github.com/PostHog/posthog-ios/actions/workflows/release.yml) by clicking "Run workflow".

## Version Bumping

Changesets handles version bumping automatically based on the changesets you create:

- **patch**: Bug fixes, documentation updates, internal changes (e.g., `3.41.1` → `3.41.2`)
- **minor**: New features, non-breaking changes (e.g., `3.41.1` → `3.42.0`)
- **major**: Breaking changes (e.g., `3.41.1` → `4.0.0`)

## Pre-release Versions

For pre-release versions (alpha, beta, RC), you can manually enter pre-release mode:

```bash
pnpm changeset pre enter alpha  # or beta, rc
pnpm changeset version
```

To exit pre-release mode:

```bash
pnpm changeset pre exit
```

## Troubleshooting

### No changesets found

If the release workflow fails with "No changesets found", ensure your PR includes at least one changeset file in the `.changeset/` directory.

### Release not triggered

Make sure the PR includes a changeset file and was merged to `main`, or trigger the workflow manually from the Actions tab.

## CocoaPods

PostHog 4.0 and later is not published to CocoaPods. The release workflow has no CocoaPods step, and the repository no longer has a podspec or a `make releaseCocoaPods` target.

[CocoaPods trunk becomes read-only on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/). After that date nobody can push a new version of the `PostHog` pod:

- 3.x versions already on trunk stay installable with `pod 'PostHog', '~> 3.0'`, but they are frozen. No new 3.x pod can be published after the lock.
- Before the lock, a 3.x fix can only reach CocoaPods from a branch cut from the latest 3.x tag, because the release workflow runs on `main`, which is 4.x. That branch still has `PostHog.podspec`, `make releaseCocoaPods` and the pod-ownership and `COCOAPODS_TRUNK_TOKEN` docs (see [RELEASING.md at 3.92.5](https://github.com/PostHog/posthog-ios/blob/3.92.5/RELEASING.md#cocoapods-management)). Get maintainer approval before publishing from it.
- Once no further 3.x pod is planned, and at the latest after the lock, delete the `COCOAPODS_TRUNK_TOKEN` secret and revoke its trunk session with `pod trunk me clean-sessions`.
