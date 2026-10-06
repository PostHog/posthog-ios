---
'posthog-ios': patch
---

Network reachability now uses `NWPathMonitor` instead of the deprecated `SCNetworkReachability` API. `dataMode` behavior is unchanged: `.wifi` still sends on any connection that isn't cellular, including wired. The unavailable `ReachabilityChangedNotification` global is removed.
