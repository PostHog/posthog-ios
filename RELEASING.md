Releasing
=========

 1. Update the version in `PHGPostHog.m`, `PostHog.podspec` and `PostHog/Info.plist` to the next release version.
 2. Update the `CHANGELOG.md` for the impending release.
 3. `git commit -am "Prepare for release X.Y.Z."` (where X.Y.Z is the new version).
 4. `git tag -a X.Y.Z -m "Version X.Y.Z"` (where X.Y.Z is the new version).
 5. `git push && git push --tags`.
 6. `pod trunk push PostHog.podspec`.
 7. Next we'll create a dynamic framework for manual installation leveraging Carthage.
     * `cd Examples/CarthageExample`.
     * Update `Cartfile` first line to the correct tag `X.Y.Z` that just got pushed to Github.
     * `make clean` to be safe then `make build`.
     * Zip `Carthage/Builds/iOS/PostHog.framework` and `Carthage/Builds/iOS/PostHog.dSYM` into `Archive.zip`.
 8. Next, we'll create a Carthage build by running `make archive`.
 9. Create a new Github release at https://github.com/PostHog/posthog-ios/releases
     * Add latest version information from `CHANGELOG.md`
     * Upload `Archive.zip` from step 7 and `PostHog.zip` from step 8 into binaries section to make available for users to download.
 10. `git push`.
