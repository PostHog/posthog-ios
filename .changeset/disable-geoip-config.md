---
"posthog-ios": minor
---

Add the `disableGeoIp` config so an app can opt out of server-side GeoIP enrichment. When enabled, captured events carry `$geoip_disable` and feature flag requests send `geoip_disable`, so the server doesn't infer the user's location from their IP address.
