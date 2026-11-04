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
   - Apply changesets and bump the version (in `package.json`, `PostHogVersion.swift`, and `PostHog.podspec`)
   - Update the `CHANGELOG.md`
   - Commit the version bump to `main`
   - Create a git tag and GitHub release
   - Publish the pod to CocoaPods (best-effort, see [CocoaPods publish failed](#cocoapods-publish-failed))
   - SPM uses the tag name to determine the version, directly from the repo

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

### Failed or cancelled release

The independent [release failure notification workflow](.github/workflows/release-failure-notification.yml) checks every completed main-branch release attempt and posts a failure message to the release approvals Slack channel if a job failed, timed out, or was cancelled. This includes runner startup failures, whole-run cancellations, and best-effort CocoaPods job failures that do not fail the run. It also alerts if the GitHub release exists but the released Slack notification was skipped. Job inspection retries transient GitHub API failures up to three times. If inspection still fails, it posts a fallback alert with the overall run status and logs link so the release can be checked manually.

The failure message is a new channel message, not a thread reply, so it does not depend on the approval notification succeeding. Existing approval, rejection, and successful-release messages remain in the approval thread. The released/status messages and the independent failure message surface Slack API errors rather than silently ignoring them, allowing the completion check to detect a failed release notification. The completion workflow must be present on the default branch to run; local tests do not send Slack messages.

### CocoaPods publish failed

CocoaPods publishing is best-effort and does not block the release. If the "Publish to CocoaPods" job fails, the run still succeeds once the tag and GitHub release exist, the "released" Slack notification still goes out, and the Slack release thread gets a reply saying whether the version was published to CocoaPods, so you know when the pod is missing.

CocoaPods Trunk becomes permanently read-only on December 2nd 2026, after which new pod versions can no longer be published.

To publish a missed pod manually, check out the release tag and push it:

```bash
git fetch --tags
git checkout <version>  # e.g. 3.93.3
make releaseCocoaPods
```

You'll need to be authenticated with CocoaPods trunk and have push access to the `PostHog` pod.

# CocoaPods Management

The PostHog iOS SDK is published to CocoaPods automatically via GitHub Actions when a release is created. This section covers the management of CocoaPods permissions and tokens.

### Check Your Current Session

```bash
# Check if you're logged in and your permissions
pod trunk me
```

Expected output should show:

```text
- Name:     Your Name
- Email:    your.email@posthog.com
- Since:    Date
- Pods:
  - PostHog
- Sessions:
  - Session details...
```

### Check Pod Ownership

```bash
# Check who owns the PostHog pod
pod trunk info PostHog
```

This will show:

- Current version
- All owners with push permissions

### Adding a co-owner

1. **With an existing owner**:

   ```bash
   # Run this as an existing owner
   pod trunk add-owner PostHog dev.email@posthog.com
   ```

2. **Verify**:
   ```bash
   # Check that the new owner was added
   pod trunk info PostHog
   ```

### Removing a co-owner

1. **With an existing owner**:

   ```bash
   # Run this as an existing owner
   pod trunk remove-owner PostHog dev.email@posthog.com
   ```

2. **Verify**:
   ```bash
   # Check that the new owner was removed
   pod trunk info PostHog
   ```

### Rotating COCOAPODS_TRUNK_TOKEN

The `COCOAPODS_TRUNK_TOKEN` is used in GitHub Actions for automated releases. Here's how to rotate it:

The token is stored as a GitHub secret and used in `.github/workflows/release.yml`:

```yaml
env:
  COCOAPODS_TRUNK_TOKEN: ${{ secrets.COCOAPODS_TRUNK_TOKEN }}
```

#### Step 1: Create a new session

1. **Login to CocoaPods Trunk**
   As the account that will own the token, create a new session with:
   ```bash
   pod trunk register your.email@posthog.com 'Your Name'
   # Verify email if needed
   ```

2. **Extract the token**:
   The token is stored in `~/.netrc` file:
   ```bash
   # View your .netrc file
   grep -A2 'trunk.cocoapods.org' ~/.netrc
   # or look for the line with `trunk.cocoapods.org` in ~/.netrc
   cat ~/.netrc
   ```

#### Step 2: Update GitHub Secret

1. **Go to GitHub repository settings**:
   - Request temp access if needed
   - Navigate to `https://github.com/organizations/PostHog/settings/secrets/actions`
   - Or: Org → Settings → Secrets and variables → Actions

2. **Update the secret**:
   - Find `COCOAPODS_TRUNK_TOKEN` in the list
   - Update the secret

#### Step 3: Revoking Old Sessions

1. **Revoke old sessions**:
   ```bash
   # Clear current sessions (from the user that owned the previous token)
   pod trunk me clean-sessions
   ```

#### Step 4: Update workflow docs

Update `./.github/workflows/release.yml` with a comment on the new token owner.

```yaml
env:
  COCOAPODS_TRUNK_TOKEN: ${{ secrets.COCOAPODS_TRUNK_TOKEN }} # Using @username token
```
