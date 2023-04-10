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
