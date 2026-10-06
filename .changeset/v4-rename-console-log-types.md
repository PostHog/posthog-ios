---
'posthog-ios': major
---

**Breaking:** rename `PostHogLogLevel` to `PostHogConsoleLogLevel` and `PostHogLogEntry` to `PostHogConsoleLogEntry`, so the session replay console log types aren't confused with the Logs types `PostHogLogSeverity` and `PostHogLogRecord`. Update custom `logSanitizer` and `minLogLevel` code to the new names (`PostHogConsoleLogLevelInfo`/`Warn`/`Error` in Objective-C). Behavior is unchanged.
