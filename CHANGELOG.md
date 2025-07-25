## Next

- feat: add person and group properties for feature flags ([#373](https://github.com/PostHog/posthog-ios/pull/373))
- feat: support default properties for feature flag evaluation ([#375](https://github.com/PostHog/posthog-ios/pull/375))

## 3.29.0 - 2025-07-15

- feat: add support for custom survey UI ([#369](https://github.com/PostHog/posthog-ios/pull/369))

## 3.28.3 - 2025-07-14

- fix: don't clear flags on remote config error or if hasFeatureFlags is nil ([#368](https://github.com/PostHog/posthog-ios/pull/368))

## 3.28.2 - 2025-06-26

- fix: survey question header padding ([#365](https://github.com/PostHog/posthog-ios/pull/365))
- fix: session replay perforamnce improvements ([#364](https://github.com/PostHog/posthog-ios/pull/364))

## 3.28.1 - 2025-06-23

- fix: surveys decoding error ([#363](https://github.com/PostHog/posthog-ios/pull/363))

## 3.28.0 - 2025-06-19

- feat: add support for beforeSend function to edit or drop events ([#357](https://github.com/PostHog/posthog-ios/pull/357))

## 3.27.0 - 2025-06-16

- fix: unify storage path for `appGroupIdentifier` across targets ([#356](https://github.com/PostHog/posthog-ios/pull/356))
- fix: do not call flags callback with invalid flags ([#355](https://github.com/PostHog/posthog-ios/pull/355))
- use new `/flags` endpoint instead of `/decide` ([#345](https://github.com/PostHog/posthog-ios/pull/345))

## 3.26.2 - 2025-06-03

- fix: pause network capture when app is backgrounded ([#352](https://github.com/PostHog/posthog-ios/pull/352))
- fix: prevent duplicate application lifecycle events ([#354](https://github.com/PostHog/posthog-ios/pull/354))

## 3.26.1 - 2025-05-30

- fix: clear cached flags if remote config response hasFeatureFlags is false ([#347](https://github.com/PostHog/posthog-ios/pull/347))§

## 3.26.0 - 2025-05-20

- feat: capture console logs for session replay ([#350](https://github.com/PostHog/posthog-ios/pull/350))

## 3.25.1 - 2025-05-13

- fix: edge case where session manager would not rotate session id ([#349](https://github.com/PostHog/posthog-ios/pull/349))

## 3.25.0 - 2025-04-30

- feat: add support for conditional survey questions ([#343](https://github.com/PostHog/posthog-ios/pull/343))

## 3.24.3 - 2025-04-29

- fix: feature flags not loading on sdk init ([#346](https://github.com/PostHog/posthog-ios/pull/346))

## 3.24.2 - 2025-04-24

- fix: optional link in survey question type ([#341](https://github.com/PostHog/posthog-ios/pull/341))
- fix: app hangs on iPad with floating keyboard when session replay is enabled ([#340](https://github.com/PostHog/posthog-ios/pull/340))

## 3.24.1 - 2025-04-23

- fix: Send correct `$feature_flag_response` for the `$feature_flag_called` event when calling `isFeatureEnabled` ([#337](https://github.com/PostHog/posthog-ios/pull/337))
- fix: support ISO8601 dates with missing milliseconds ([#338](https://github.com/PostHog/posthog-ios/pull/338))

## 3.24.0 - 2025-04-17

- chore: Autocapture GA ([#334](https://github.com/PostHog/posthog-ios/pull/334))
- feat: reuse `anonymousId` between user changes ([#332](https://github.com/PostHog/posthog-ios/pull/332))

## 3.23.0 - 2025-04-14

- fix: postHogMask() view modifier breaks navigation bar ([#331](https://github.com/PostHog/posthog-ios/pull/331))
- fix: manually start session recording even when `config.sessionReplay` is disabled ([#330](https://github.com/PostHog/posthog-ios/pull/330))
- feat: start/stop integrations when calling optIn() or optOut() ([#329](https://github.com/PostHog/posthog-ios/pull/329))
- feat: add `$feature_flag_id`, `$feature_flag_version`, `$feature_flag_reason` and `$feature_flag_request_id` properties to `$feature_flag_called` event ([#327](https://github.com/PostHog/posthog-ios/pull/327))

## 3.22.1 - 2025-04-10

- no user facing changes

## 3.22.0 - 2025-04-09

- feat: add support for surveys on iOS ([#325](https://github.com/PostHog/posthog-ios/pull/325))

## 3.21.0 - 2025-03-28

- fix: visionOS builds ([#291](https://github.com/PostHog/posthog-ios/pull/291))
Thanks @harlanhaskins ❤️

- feat: improve session replay throttle logic ([#322](https://github.com/PostHog/posthog-ios/pull/322))
> Note: `debouncerDelay` is deprecated and will be removed in next major update. Use `throttleDelay` instead which provides identical functionality for controlling session replay capture frequency.

## 3.20.1 - 2025-03-13

- fix: disk storage not working on tvOS ([#316](https://github.com/PostHog/posthog-ios/pull/316))
- fix: wrong is_identified fallback value ([#317](https://github.com/PostHog/posthog-ios/pull/317))

## 3.20.0 - 2025-03-04

- feat: support multiple SDK instances ([#310](https://github.com/PostHog/posthog-ios/pull/310))
> Note: Now event storage is per API key. Any pending events in legacy storage will be migrated to the first API key used.  

## 3.19.9 - 2025-02-28

- fix: SwiftUI view masking when using clipShape view modifier ([#312](https://github.com/PostHog/posthog-ios/pull/312))
- fix: reported crash on PostHogSessionManager ([#311](https://github.com/PostHog/posthog-ios/pull/311))

## 3.19.8 - 2025-02-26

- feat: add support for quota-limited feature flags ([#308](https://github.com/PostHog/posthog-ios/pull/308))

## 3.19.7 - 2025-02-20

- fix: recordings not always properly masked during screen transitions ([#306](https://github.com/PostHog/posthog-ios/pull/306))

## 3.19.6 - 2025-02-18

- fix: crash on autocapture when a segmented control has not selection ([#304](https://github.com/PostHog/posthog-ios/pull/304))

## 3.19.5 - 2025-02-11

- fix: flutter session recordings not working ([#297](https://github.com/PostHog/posthog-ios/pull/297))

## 3.19.4 - 2025-02-07

- fix: occasional crash when converting to Int in session replay wireframe ([#294](https://github.com/PostHog/posthog-ios/pull/294))

## 3.19.3 - 2025-02-04

- fix: custom hosts with a path ([#290](https://github.com/PostHog/posthog-ios/pull/290))
- fix: identify macOS when running Mac Catalyst or iOS on Mac ([#287](https://github.com/PostHog/posthog-ios/pull/287))

## 3.19.2 - 2025-01-30

- fix: XCFramework builds failing ([#288](https://github.com/PostHog/posthog-ios/pull/288))
- chore: Session Replay GA ([#286](https://github.com/PostHog/posthog-ios/pull/286))

## 3.19.1 - 2025-01-13

- fix: RN Expo builds failing ([#281](https://github.com/PostHog/posthog-ios/pull/281))

## 3.19.0 - 2025-01-08

- feat: ability to manually start and stop session recordings ([#276](https://github.com/PostHog/posthog-ios/pull/276))
- feat: change screenshot encoding format from JPEG to WebP ([#273](https://github.com/PostHog/posthog-ios/pull/273))

## 3.18.0 - 2024-12-27

- feat: add `postHogNoMask` SwiftUI view modifier to explicitly mark any View as non-maskable ([#277](https://github.com/PostHog/posthog-ios/pull/277))

## 3.17.2 - 2024-12-23

- fix: ignore additional keyboard windows for $screen event ([#279](https://github.com/PostHog/posthog-ios/pull/279))

## 3.17.1 - 2024-12-18

- fix: avoid masking SwiftUI Gradient views ([#275](https://github.com/PostHog/posthog-ios/pull/275))

## 3.17.0 - 2024-12-10

- feat: ability to add a custom label to autocapture elements ([#271](https://github.com/PostHog/posthog-ios/pull/271))

## 3.16.2 - 2024-12-05

- fix: ignore autocapture events from keyboard window ([#269](https://github.com/PostHog/posthog-ios/pull/269))

## 3.16.1 - 2024-12-04

- fix: screen flicker when capturing a screenshot when a sensitive text field is on screen ([#270](https://github.com/PostHog/posthog-ios/pull/270))

## 3.16.0 - 2024-12-03

- fix: deprecate `maskPhotoLibraryImages` due to unintended masking issues ([#268](https://github.com/PostHog/posthog-ios/pull/268))

## 3.15.9 - 2024-11-28

- fix: skip capturing a snapshot during view controller transitions ([#265](https://github.com/PostHog/posthog-ios/pull/265))

## 3.15.8 - 2024-11-28

- no user facing changes

## 3.15.7 - 2024-11-25

- fix: detect and mask out system photo library and user photos ([#261](https://github.com/PostHog/posthog-ios/pull/261))
    - This can be disabled through the following `sessionReplayConfig` options: 
    
    ```swift
    config.sessionReplayConfig.maskAllSandboxedViews = false
    config.sessionReplayConfig.maskPhotoLibraryImages = false
    ```
## 3.15.6 - 2024-11-20

- fix: read accessibilityLabel from parent's view to avoid performance hit on RN ([#259](https://github.com/PostHog/posthog-ios/pull/259))

## 3.15.5 - 2024-11-19

- fix: properly mask SwiftUI Text (and text-based views) ([#257](https://github.com/PostHog/posthog-ios/pull/257))

## 3.15.4 - 2024-11-19

- fix: avoid zero touch locations ([#256](https://github.com/PostHog/posthog-ios/pull/256))
- fix: reading screen size could sometimes lead to a deadlock ([#252](https://github.com/PostHog/posthog-ios/pull/252))

## 3.15.3 - 2024-11-18

- fix: mangled wireframe layouts ([#250](https://github.com/PostHog/posthog-ios/pull/250))
- recording: do not rotate the session id for hybrid SDKs ([#253](https://github.com/PostHog/posthog-ios/pull/253))

## 3.15.2 - 2024-11-13

- fix: allow changing person properties after identify ([#249](https://github.com/PostHog/posthog-ios/pull/249))

## 3.15.1 - 2024-11-12

- fix: accessing UI APIs off main thread to get screen size ([#247](https://github.com/PostHog/posthog-ios/pull/247))

## 3.15.0 - 2024-11-11

- add autocapture support for UIKit ([#224](https://github.com/PostHog/posthog-ios/pull/224))

## 3.14.2 - 2024-11-08

- fix issue with resetting accent color in SwiftUI app ([#238](https://github.com/PostHog/posthog-ios/pull/238)) 
- fix $feature_flag_called not captured after reloading flags ([#232](https://github.com/PostHog/posthog-ios/pull/232))

## 3.14.1 - 2024-11-05

- recording: fix RN iOS masking ([#230](https://github.com/PostHog/posthog-ios/pull/230))

## 3.14.0 - 2024-11-05

- add option to pass a custom timestamp when calling capture() ([#228](https://github.com/PostHog/posthog-ios/pull/228))
- fix crash when loading dynamic colors from storyboards ([#229](https://github.com/PostHog/posthog-ios/pull/229)) 

## 3.13.3 - 2024-10-25

- fix race condition in PostHogFileBackedQueue.deleteFiles ([#218](https://github.com/PostHog/posthog-ios/pull/218))

## 3.13.2 - 2024-10-18

- add missing capture method for objC with groups overload ([#217](https://github.com/PostHog/posthog-ios/pull/217))

## 3.13.1 - 2024-10-16

- add optional distinctId parameter to capture methods ([#216](https://github.com/PostHog/posthog-ios/pull/216))

## 3.13.0 - 2024-10-14

- recording: session replay respect feature flag variants ([#209](https://github.com/PostHog/posthog-ios/pull/209))
- add `postHogMask` view modifier to manually mask a SwiftUI view ([#202](https://github.com/PostHog/posthog-ios/pull/202))

## 3.12.7 - 2024-10-09

- add appGroupIdentifier in posthog config ([#207](https://github.com/PostHog/posthog-ios/pull/207))

## 3.12.6 - 2024-10-02

- recording: capture network logs from dataTask requests without CompletionHandler ([#203](https://github.com/PostHog/posthog-ios/pull/203))

## 3.12.5 - 2024-09-24

- no user facing changes

## 3.12.4 - 2024-09-19

- no user facing changes

## 3.12.3 - 2024-09-18

- no user facing changes

## 3.12.2 - 2024-09-17

- fix: some public APIs such as unregister weren't checking for isEnabled ([#196](https://github.com/PostHog/posthog-ios/pull/196))

## 3.12.1 - 2024-09-12

- recording: missing import for url session extensions ([#194](https://github.com/PostHog/posthog-ios/pull/194))
- recording: network logs not counting the request transferSize but only the response transferSize ([#193](https://github.com/PostHog/posthog-ios/pull/193))

## 3.12.0 - 2024-09-12

- chore: add Is Emulator support ([#190](https://github.com/PostHog/posthog-ios/pull/190))
- recording: PostHog URLSession extensions for capturing network logs ([#189](https://github.com/PostHog/posthog-ios/pull/189))

## 3.11.0 - 2024-09-11

- chore: add personProfiles support ([#187](https://github.com/PostHog/posthog-ios/pull/187))

## 3.10.0 - 2024-09-09

- recording: mask swiftui picker if masking enabled ([#184](https://github.com/PostHog/posthog-ios/pull/184))
- chore: add is identified property ([#186](https://github.com/PostHog/posthog-ios/pull/186))
- recording: create timers in the main thread since it requires a run loop ([#188](https://github.com/PostHog/posthog-ios/pull/188))

## 3.9.1 - 2024-09-06

- recording: detect swiftui images not too agressively ([#181](https://github.com/PostHog/posthog-ios/pull/181))

## 3.9.0 - 2024-09-06

- chore: add SwiftUI View extensions to capture screen view and views in general (postHogViewEvent, postHogScreenView) ([#180](https://github.com/PostHog/posthog-ios/pull/180))
- recording: send meta event again if session rotates ([#183](https://github.com/PostHog/posthog-ios/pull/183))

## 3.8.3 - 2024-09-03

- recording: use non deprecated methods for getCurrentWindow if available ([#178](https://github.com/PostHog/posthog-ios/pull/178))

## 3.8.2 - 2024-09-03

- chore: cache flags, distinct id and anon id in memory to avoid file IO every time ([#177](https://github.com/PostHog/posthog-ios/pull/177))

## 3.8.1 - 2024-08-30

- fix: do not clear events when reset is called ([#175](https://github.com/PostHog/posthog-ios/pull/175))
- fix: reload feature flags as anon user after reset is called ([#175](https://github.com/PostHog/posthog-ios/pull/175))

## 3.8.0 - 2024-08-29

- fix: rotate session id when reset is called ([#174](https://github.com/PostHog/posthog-ios/pull/174))
- chore: expose session id ([#165](https://github.com/PostHog/posthog-ios/pull/165)), ([#170](https://github.com/PostHog/posthog-ios/pull/170)) and ([#171](https://github.com/PostHog/posthog-ios/pull/171))

## 3.7.2 - 2024-08-16

- recording: improve ios session recording performance by avoiding redrawing after screen updates ([#166](https://github.com/PostHog/posthog-ios/pull/166))
  - `debouncerDelay` is changed from 500ms to 1s since the iOS screenshot has to be taken in the main thread and its more sensitive to performance issues

## 3.7.1 - 2024-08-13

- recording: improve ios session recording performance by doing some work off of the main thread ([#158](https://github.com/PostHog/posthog-ios/pull/158))

## 3.7.0 - 2024-08-07

- chore: Support the `propertiesSanitizer` config ([#154](https://github.com/PostHog/posthog-ios/pull/154))

## 3.6.3 - 2024-07-26

- recording: fix respect session replay project settings from app start ([#150](https://github.com/PostHog/posthog-ios/pull/150))

## 3.6.2 - 2024-07-25

- recording: fix MTLTextureDescriptor has width of zero issue ([#149](https://github.com/PostHog/posthog-ios/pull/149))

## 3.6.1 - 2024-06-26

- recording: improvements to screenshot masking ([#147](https://github.com/PostHog/posthog-ios/pull/147))

## 3.6.0 - 2024-06-26

- recording: screenshot masking ([#146](https://github.com/PostHog/posthog-ios/pull/146))

## 3.5.2 - 2024-06-18

- chore: migrate UUID from v4 to v7 ([#145](https://github.com/PostHog/posthog-ios/pull/145))

## 3.5.1 - 2024-06-12

- recording: fix `screenshotMode` typo ([#143](https://github.com/PostHog/posthog-ios/pull/143))

## 3.5.0 - 2024-06-11

- chore: change host to new address ([#139](https://github.com/PostHog/posthog-ios/pull/139))
- fix: rename groupProperties to groups for capture methods ([#140](https://github.com/PostHog/posthog-ios/pull/140))
- recording: add `screenshotMode` option for session replay instead of wireframe ([#142](https://github.com/PostHog/posthog-ios/pull/142))

## 3.4.0 - 2024-05-23

- allow anonymous id generation to be configurable ([#133](https://github.com/PostHog/posthog-ios/pull/133))
- fix: PrivacyInfo warning when using Cocoapods ([#138](https://github.com/PostHog/posthog-ios/pull/138))

## 3.3.0 - 2024-05-21

- chore: apply patches from 3.2.5 to 3.3.0 and session recording fixes [#135](https://github.com/PostHog/posthog-ios/pull/135)
  - iOS session recording is still experimental

## 3.2.5 - 2024-05-14

- fix: `reset` deletes only sdk files instead of the whole folder [#132](https://github.com/PostHog/posthog-ios/pull/132)

## 3.3.0-alpha.2 - 2024-04-16

- chore: silence `shared` warning for strict concurrency [#129](https://github.com/PostHog/posthog-ios/pull/129)

## 3.3.0-alpha.1 - 2024-03-27

- iOS session recording - very first alpha release [#115](https://github.com/PostHog/posthog-ios/pull/115)

## 3.2.4 - 2024-03-12

- `maxQueueSize` wasn't respected when capturing events [#116](https://github.com/PostHog/posthog-ios/pull/116)

## 3.2.3 - 2024-03-05

- `optOut` wasn't respected in capture methods [#114](https://github.com/PostHog/posthog-ios/pull/114)

## 3.2.2 - 2024-03-01

- API requests do a 10s timeoutInterval instead of 60s [#113](https://github.com/PostHog/posthog-ios/pull/113)

## 3.2.1 - 2024-02-26

- PrivacyInfo manifest set in the SPM and CocoaPods config [#112](https://github.com/PostHog/posthog-ios/pull/112)

## 3.2.0 - 2024-02-23

- read `$app_name` from `CFBundleDisplayName` as a fallback if `CFBundleName` isn't available [#108](https://github.com/PostHog/posthog-ios/pull/108)
- add PrivacyInfo manifest [#110](https://github.com/PostHog/posthog-ios/pull/110)

## 3.1.4 - 2024-02-19

- fix reset session when reset or close are called [#107](https://github.com/PostHog/posthog-ios/pull/107)

## 3.1.3 - 2024-02-09

- fix ISO8601 formatter to always use the 24h format [#106](https://github.com/PostHog/posthog-ios/pull/106)

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

- Add support for groups, simplefeature flags, and multivariate feature flags

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
