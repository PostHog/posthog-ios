## Next

## 3.1.2 - 2024-02-09

- fix and improve logging if the `debug` flag is enabled [#104](https://github.com/PostHog/posthog-ios/pull/104)

## 3.1.1 - 2024-02-08

- `Application Opened` respects the `captureApplicationLifecycleEvents` config. [#102](https://github.com/PostHog/posthog-ios/pull/102)

## 3.1.0 - 2024-02-07

- Add session tracking [#100](https://github.com/PostHog/posthog-ios/pull/100)

## 3.0.0 - 2024-01-29

Check out the updated [docs](https://posthog.com/docs/libraries/ios).

Check out the [USAGE](https://github.com/PostHog/posthog-ios/blob/main/USAGE.md) guide.

### Changes

- Rewritten in Swift.
- [Breaking changes](https://github.com/PostHog/posthog-ios/blob/main/USAGE.md#breaking-changes) in the API.

## 3.0.0-RC.1 - 2024-01-16

- better macOS support with more event properties [#96](https://github.com/PostHog/posthog-ios/pull/96)

## 3.0.0-beta.3 - 2024-01-11

- Do not report dupe `Application Opened` event during the first time [#95](https://github.com/PostHog/posthog-ios/pull/95)

## 3.0.0-beta.2 - 2024-01-09

- Internal changes only

## 3.0.0-beta.1 - 2024-01-08

- Promoted to beta since no issues were found in the alpha release

## 3.0.0-alpha.5 - 2023-11-03

- Just testing the release automation

## 3.0.0-alpha.4 - 2023-11-03

- Just testing the release automation

## 3.0.0-alpha.3 - 2023-11-02

- Add more targets and change default branch to main [#75](https://github.com/PostHog/posthog-ios/pull/75)

## 3.0.0-alpha.2 - 2023-11-02

- Just testing the release automation

## 3.0.0-alpha.1 - 2023-11-02

- First alpha of the new major version of the iOS SDK
- Just testing the release automation

## 2.1.0 - 2023-10-10

- isFeatureEnabled now returns false if disabled [#74](https://github.com/PostHog/posthog-ios/pull/74)
- Add preloadFeatureFlags configuration flag [#71](https://github.com/PostHog/posthog-ios/pull/71)

## 2.0.5 - 2023-10-06

- Update device type [#63](https://github.com/PostHog/posthog-ios/pull/63)
- `$active_feature_flags` event should filter non active flags ([#73](https://github.com/PostHog/posthog-ios/pull/73))

## 2.0.4 - 2023-10-05

- CoreTelephony should not be added to tvOS builds [#67](https://github.com/PostHog/posthog-ios/pull/67)
- Remote notifications methods do not throw if no default implementation [#67](https://github.com/PostHog/posthog-ios/pull/67)

## 2.0.3 - 2023-06-02

- Fixes an issue that interfered with a SwiftUI bug

## 2.0.2 - 2023-04-04

- Remove adclient

## 2.0.1 - 2023-03-20

- Accept `options` parameter on feature flag methods to enable/disable emitting usage events

## 2.0.0 - 2022-08-29

- Add support for groups, simplefeature flags, and  multivariate feature flags

## 1.4.4 - 2021-11-19

Make enabled property public.

## 1.4.3 - 2021-11-02

Add `shouldSendDeviceID` config option.

## 1.4.2 - 2021-09-17

Fix Info.plist warning for Swift Package Manager

## 1.4.1 - 2021-09-17

Fix warning with Swift Package Manager

## 1.4.0 - 2021-05-27

Fix support for Swift Package Manager

## 1.3.0 - 2021-05-11

In the `identify` call the `distinct_id` field can no longer be `nil`.

## 1.2.3 - 2021-02-24

Renamed functions which were causing conflicts with Segment iOS library

## 1.2.2 - 2020-02-22

Swift Package Manager

## 1.2.1 - 2020-12-18

Also remove the `enableAdvertisingCapturing` and `adSupportBlock` config options

## 1.2.0 - 2020-12-18

Completely remove reference to the AdSupport framework

## 1.1.0 - 2020-10-03

Shift responsibility of IDFA collection to clients ([#5](https://github.com/PostHog/posthog-ios/pull/5))
by removing any references to Apple's AdSupport framework from the library. In case you need to
use the $device_advertisingId field, [see here](https://posthog.com/docs/integrations/ios-integration) for how to enable it.

## 1.0.5 - 2020-08-25

Add Swift Package Manager support

## 1.0.4 - 2020-05-25

Fix selector typo with ad capturing, which resulted in a crash when moving your app to the foreground.

## 1.0.3 - 2020-05-20

Support passing in custom library version and name. This is used in the React Native client.

## 1.0.2 - 2020-05-18

Fix issues with launching the library and screen tracking.

## 1.0.0 - 2020-04-22

First Release.
