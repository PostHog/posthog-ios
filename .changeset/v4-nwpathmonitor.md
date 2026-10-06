---
'posthog-ios': patch
---

Network reachability now uses `NWPathMonitor` instead of the deprecated `SCNetworkReachability` API. `dataMode = .wifi` still counts any connection that isn't cellular as Wi-Fi, including wired. Some edge cases change. A path that needs a connection now counts as reachable, even when it needs user action (e.g. a VPN waiting for a password). With cellular data turned off for the app, queues now pause instead of sending requests that fail. If no path has arrived in the first 100 ms after setup, `.any` sends and `.wifi` waits for the first path, and events captured in that window leave out `$network_wifi` and `$network_cellular`. The unavailable `ReachabilityChangedNotification` global is removed.
