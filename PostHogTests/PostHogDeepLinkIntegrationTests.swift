import Foundation
@testable import PostHog
import Testing

// MARK: - Unit Tests for PostHogDeepLinkHelper

@Suite("Deep Link Helper Tests")
struct PostHogDeepLinkHelperTests {
    @Test("builds properties with valid referrer URL")
    func buildPropertiesWithValidReferrerURL() {
        let url = URL(string: "myapp://product/123?utm_source=newsletter")!
        let referrer = "https://www.google.com/path?q=search"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["url"] as? String == url.absoluteString)
        #expect(props["$referrer"] as? String == referrer)
        #expect(props["$referring_domain"] as? String == "www.google.com")
    }

    @Test("builds properties with non-URL referrer string (bundle ID)")
    func buildPropertiesWithNonURLReferrer() {
        let url = URL(string: "myapp://home")!
        let referrer = "com.example.sourceApp"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["url"] as? String == url.absoluteString)
        #expect(props["$referrer"] as? String == referrer)
        #expect(props["$referring_domain"] == nil, "$referring_domain should be absent for non-URL referrers")
    }

    @Test("builds properties without referrer")
    func buildPropertiesWithoutReferrer() {
        let url = URL(string: "https://myapp.com/welcome")!

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: nil)

        #expect(props["url"] as? String == url.absoluteString)
        #expect(props["$referrer"] == nil)
        #expect(props["$referring_domain"] == nil)
    }

    @Test("extracts referring domain from universal link referrer")
    func extractsReferringDomainFromUniversalLink() {
        let url = URL(string: "https://myapp.com/article/42")!
        let referrer = "https://news.ycombinator.com/item?id=42"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["$referring_domain"] as? String == "news.ycombinator.com")
    }

    @Test("handles custom URL scheme")
    func handlesCustomURLScheme() {
        let url = URL(string: "posthog://dashboard/analytics")!

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: nil)

        #expect(props["url"] as? String == "posthog://dashboard/analytics")
    }

    @Test("handles URL with query parameters and fragments")
    func handlesURLWithQueryAndFragment() {
        let url = URL(string: "myapp://page?foo=bar&baz=qux#section")!
        let referrer = "https://example.com"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["url"] as? String == "myapp://page?foo=bar&baz=qux#section")
        #expect(props["$referrer"] as? String == "https://example.com")
        #expect(props["$referring_domain"] as? String == "example.com")
    }
}

// MARK: - Integration Tests for Deep Link Event Capture

@Suite("Deep Link Event Capture Tests", .serialized)
final class PostHogDeepLinkEventTests {
    var server: MockPostHogServer!

    init() {
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
        server = nil
    }

    private func getSut(flushAt: Int = 1) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "deep_link_test", host: "http://localhost:9001")
        config.flushAt = flushAt
        config.maxBatchSize = flushAt
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        config.disableFlushOnBackgroundForTesting = true

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    @Test("captures Deep Link Opened event with URL")
    func capturesDeepLinkOpenedEvent() async throws {
        let sut = getSut()
        defer { sut.close() }

        let url = URL(string: "myapp://product/123")!
        sut.captureDeepLink(url: url)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events[0].event == "Deep Link Opened")
        #expect(events[0].properties["url"] as? String == "myapp://product/123")
    }

    #if os(iOS) || os(tvOS) || os(macOS)
        @Test("captures Deep Link Opened event with referrer from NSUserActivity")
        func capturesDeepLinkWithUserActivity() async throws {
            let sut = getSut()
            defer { sut.close() }

            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = URL(string: "https://myapp.com/article/42")
            activity.referrerURL = URL(string: "https://twitter.com/post/123")

            sut.captureDeepLink(userActivity: activity)

            let events = try await getServerEvents(server)

            #expect(events.count == 1)
            #expect(events[0].event == "Deep Link Opened")
            #expect(events[0].properties["url"] as? String == "https://myapp.com/article/42")
            #expect(events[0].properties["$referrer"] as? String == "https://twitter.com/post/123")
            #expect(events[0].properties["$referring_domain"] as? String == "twitter.com")
        }

        @Test("ignores NSUserActivity with non-browsing activity type")
        func ignoresNonBrowsingUserActivity() async throws {
            let sut = getSut(flushAt: 1)
            defer { sut.close() }

            let activity = NSUserActivity(activityType: "com.myapp.custom")
            activity.webpageURL = URL(string: "https://myapp.com/page")

            sut.captureDeepLink(userActivity: activity)
            // Capture another event to trigger flush
            sut.capture("test_event")

            let events = try await getServerEvents(server)

            // Should only have the test_event, not the deep link
            #expect(events.count == 1)
            #expect(events[0].event == "test_event")
        }

        @Test("captures multiple URLs from array, filtering file URLs")
        func capturesMultipleURLsFilteringFileURLs() async throws {
            let sut = getSut(flushAt: 2)
            defer { sut.close() }

            let urls = [
                URL(string: "myapp://page1")!,
                URL(fileURLWithPath: "/path/to/file.txt"),
                URL(string: "myapp://page2")!,
            ]

            sut.captureDeepLink(urls: urls)

            let events = try await getServerEvents(server)

            // Should capture 2 events (file URL filtered out)
            #expect(events.count == 2)
            #expect(events.allSatisfy { $0.event == "Deep Link Opened" })

            let capturedURLs = events.compactMap { $0.properties["url"] as? String }
            #expect(capturedURLs.contains("myapp://page1"))
            #expect(capturedURLs.contains("myapp://page2"))
            #expect(!capturedURLs.contains { $0.contains("file.txt") })
        }
    #endif

    @Test("does not capture when SDK is disabled")
    func doesNotCaptureWhenDisabled() async throws {
        let sut = getSut(flushAt: 2)

        sut.close() // Disable SDK

        let url = URL(string: "myapp://test")!
        sut.captureDeepLink(url: url)

        // Capture should be ignored, re-enable and capture something else
        let config = PostHogConfig(projectToken: "deep_link_test_2", host: "http://localhost:9001")
        config.flushAt = 1
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        let sut2 = PostHogSDK.with(config)
        defer { sut2.close() }

        sut2.capture("verify_event")

        let events = try await getServerEvents(server)

        // Should only have verify_event, not the deep link
        #expect(events.count == 1)
        #expect(events[0].event == "verify_event")
    }
}
