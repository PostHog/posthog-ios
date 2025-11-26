# Releasing

Since `main` is protected, releases are done via pull requests.

1. Update `CHANGELOG.md` with the version and date
2. Run: `./scripts/prepare-release.sh 3.26.0`
   - This creates a release branch, bumps version, commits, and pushes
   - Preview releases follow the pattern `3.0.0-alpha.1`, `3.0.0-beta.1`, `3.0.0-RC.1`
3. Create a PR from the release branch to `main`
4. Get approval and merge the PR
5. After merge, create and push the tag from `main`:

   ```bash
   git checkout main && git pull
   git tag -a 3.26.0 -m "3.26.0"
   git push --tags
   ```

6. Go to [GH Releases](https://github.com/PostHog/posthog-ios/releases) and draft a new release
7. Choose the tag you just created (e.g. `3.26.0`) and use it as the release name
8. Write a description of the release
9. Publish the release
10. A GitHub action (release.yml) triggers the release automatically:
    - SPM uses the tag name to determine the version, directly from the repo
    - CocoaPods are published
11. Done

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
   - Navigate to `https://github.com/PostHog/posthog-ios/settings/secrets/actions`
   - Or: Repository → Settings → Secrets and variables → Actions

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
