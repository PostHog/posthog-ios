# Releasing


 1. Update the CHANGELOG.md with the version and date.
 2. Choose a tag name (e.g. `3.0.0`), this is the version number of the release.
    1. Preview releases follow the pattern `3.0.0-alpha.1`, `3.0.0-beta.1`, `3.0.0-RC.1`
    2. Execute the script with the tag's name, the script will update the version file and create a tag.

    ```bash
    ./scripts/prepare-release.sh 3.0.0
    ```

 3. Go to [GH Releases](https://github.com/PostHog/posthog-ios/releases)
 4. Choose a release name (e.g. `3.0.0`), and the tag you just created, ideally the same.
 5. Write a description of the release.
 6. Publish the release.
 7. GH Action (release.yml) is doing everything else automatically.
      1. SPM uses the tag name to determine the version, directly from the repo.
      2. CocoaPods are published.
 8. Done.

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
