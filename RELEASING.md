Releasing
=========

 1. Update the CHANGELOG.md with the version and date
 2. Create a tag with the version number (e.g. `3.0.0`)
    1. Preview releases follow the pattern `3.0.0-alpha.1`, `3.0.0-beta.1`, `3.0.0-RC.1`
    2. `git tag -a 3.0.0 -m "3.0.0"`
    3. `git push && git push --tags`
 3. Go to [GH Releases](https://github.com/PostHog/posthog-ios/releases)
 4. Choose a tag name (e.g. `3.0.0`), this is the tag of the release (From Step 2.).
 5. Choose a release name (e.g. `3.0.0`), ideally it matches the above.
 6. Write a description of the release.
 7. Publish the release.
 8. GH Action (release.yml) is doing everything else automatically.
      1. SPM uses the tag name to determine the version, directly from the repo.
      2. CocoaPods are published.
 9. Done.
