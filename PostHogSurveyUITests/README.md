# Survey interaction tests

Run `make testSurveyUI` with an installed iPhone simulator. To select a device:

```sh
make testSurveyUI SURVEY_UI_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

The shared `PostHogSurveyUI` scheme builds a test-only app and an XCUITest bundle.
The app uses `@testable import PostHog` to decode fixtures and mount the real
`SurveySheet` with `SurveyDisplayController`. Only fixture setup and a callback
recorder belong to the host; selections and navigation execute SDK code.

Tests tap the actual controls and inspect the received answer sequence, current
question, and submit button. They cover numeric/emoji/single-choice auto-submit,
branching and state reset between same-type questions, false/missing flags, open-choice text,
multiple choice, and optional manual skipping. XCUITest requires XCTest, so these
interaction tests use XCTest while the SDK's unit tests continue using Swift Testing.
