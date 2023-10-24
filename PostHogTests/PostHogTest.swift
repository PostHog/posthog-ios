import Nimble
import Quick

@testable import PostHog

class PostHogTest: QuickSpec {
    override func spec() {
        var harness: TestPostHog!
        var posthog: PostHogSDK!

        beforeEach {
            harness = TestPostHog()
            posthog = harness.posthog
        }

        afterEach {
            harness.stop()
        }

        it("creates a sensible default config") {
            let config = PostHogConfig(apiKey: "test-api-key")

            expect(config.host) == URL(string: "https://app.posthog.com")!
            expect(config.apiKey) == "test-api-key"
            expect(config.flushAt) == 20
            expect(config.maxQueueSize) == 1000
            expect(config.maxBatchSize) == 100
            expect(config.flushIntervalSeconds) == 30
            expect(config.dataMode) == .wifi
        }

        it("initialized correctly with api host") {
            // The harness posthog is already setup with a different host
//            expect(posthog.config.host) == URL(string: "http://localhost:9001")
        }

        it("setups default IDs") {
            expect(posthog.getAnonymousId()).toNot(beNil())
            expect(posthog.getDistinctId()) == posthog.getAnonymousId()
        }

        it("persits IDs but resets the session ID on load") {
            let anonymousId = posthog.getAnonymousId()
            let distinctId = posthog.getDistinctId()

            let config = PostHogConfig(apiKey: "test-api-key")
            let otherPostHog = PostHogSDK.with(config)

            let otherAnonymousId = otherPostHog.getAnonymousId()
            let otherDistinctId = otherPostHog.getDistinctId()

            expect(anonymousId) == otherAnonymousId
            expect(distinctId) == otherDistinctId
        }

//    it("fires Application Opened for UIApplicationDidFinishLaunching") {
//      testMiddleware.swallowEvent = true
//      NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidFinishLaunching, object: testApplication, userInfo: [
//        UIApplication.LaunchOptionsKey.sourceApplication: "testApp",
//        UIApplication.LaunchOptionsKey.url: "test://test",
//      ])
//
//      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
//      expect(event?.event) == "Application Opened"
//      expect(event?.properties?["from_background"] as? Bool) == false
//      expect(event?.properties?["referring_application"] as? String) == "testApp"
//      expect(event?.properties?["url"] as? String) == "test://test"
//    }
//
//    it("fires Application Opened during UIApplicationWillEnterForeground") {
//      testMiddleware.swallowEvent = true
//      NotificationCenter.default.post(name: NSNotification.Name.UIApplicationWillEnterForeground, object: testApplication)
//      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
//      expect(event?.event) == "Application Opened"
//      expect(event?.properties?["from_background"] as? Bool) == true
//    }
//
//    it("fires Application Backgrounded during UIApplicationDidEnterBackground") {
//      testMiddleware.swallowEvent = true
//      NotificationCenter.default.post(name: Notification.Name.UIApplicationDidEnterBackground, object: testApplication)
//      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
//      expect(event?.event) == "Application Backgrounded"
//    }
//
//    it("flushes when UIApplicationDidEnterBackground is fired") {
//      posthog.capture("test")
//      NotificationCenter.default.post(name: Notification.Name.UIApplicationDidEnterBackground, object: testApplication)
//      expect(testApplication.backgroundTasks.count).toEventually(equal(1))
//      expect(testApplication.backgroundTasks[0].isEnded).toEventually(beFalse())
//    }
//
//    it("respects maxQueueSize") {
//      let max = 72
//      config.maxQueueSize = UInt(max)
//
//      for i in 1...max * 2 {
//        posthog.capture("test #\(i)")
//      }
//
//      let integration = posthog.test_payloadManager()?.test_postHogIntegration()
//      expect(integration).notTo(beNil())
//
//      posthog.flush()
//      waitUntil(timeout: DispatchTimeInterval.seconds(60)) {done in
//        let queue = DispatchQueue(label: "test")
//
//        queue.async {
//          while(integration?.test_queue()?.count != max) {
//            sleep(1)
//          }
//
//          done()
//        }
//      }
//    }
//
//    it("protocol conformance should not interfere with UIApplication interface") {
//      // In Xcode8/iOS10, UIApplication.h typedefs UIBackgroundTaskIdentifier as NSUInteger,
//      // whereas Swift has UIBackgroundTaskIdentifier typealiaed to Int.
//      // This is likely due to a custom Swift mapping for UIApplication which got out of sync.
//      // If we extract the exact UIApplication method names in PHGApplicationProtocol,
//      // it will cause a type mismatch between the return value from beginBackgroundTask
//      // and the argument for endBackgroundTask.
//      // This would impact all code in a project that imports the framework.
//      // Note that this doesn't appear to be an issue any longer in Xcode9b3.
//      let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
//      UIApplication.shared.endBackgroundTask(task)
//    }
//
//    it("flushes using flushTimer") {
//      let integration = posthog.test_payloadManager()?.test_postHogIntegration()
//
//      posthog.capture("test")
//
//      expect(integration?.test_flushTimer()).toEventuallyNot(beNil())
//      expect(integration?.test_batchRequest()).to(beNil())
//
//      integration?.test_flushTimer()?.fire()
//
//      expect(integration?.test_batchRequest()).toEventuallyNot(beNil())
//    }
//
//    it("respects flushInterval") {
//      let timer = posthog
//        .test_payloadManager()?
//        .test_postHogIntegration()?
//        .test_flushTimer()
//
//      expect(timer).toNot(beNil())
//      expect(timer?.timeInterval) == config.flushInterval
//    }
//
//    it("redacts sensible URLs from deep links capturing") {
//      testMiddleware.swallowEvent = true
//      posthog.config.captureDeepLinks = true
//      posthog.open(URL(string: "fb123456789://authorize#access_token=hastoberedacted")!, options: [:])
//
//
//      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
//      expect(event?.event) == "Deep Link Opened"
//      expect(event?.properties?["url"] as? String) == "fb123456789://authorize#access_token=((redacted/fb-auth-token))"
//    }
//
//    it("redacts sensible URLs from deep links capturing using custom filters") {
//      testMiddleware.swallowEvent = true
//      posthog.config.payloadFilters["(myapp://auth\\?token=)([^&]+)"] = "$1((redacted/my-auth))"
//      posthog.config.captureDeepLinks = true
//      posthog.open(URL(string: "myapp://auth?token=hastoberedacted&other=stuff")!, options: [:])
//
//
//      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
//      expect(event?.event) == "Deep Link Opened"
//      expect(event?.properties?["url"] as? String) == "myapp://auth?token=((redacted/my-auth))&other=stuff"
//    }
//
//    it("defaults PHGQueue to an empty array when missing from file storage") {
//      let integration = posthog.test_payloadManager()?.test_postHogIntegration()
//      expect(integration).notTo(beNil())
//      integration?.test_fileStorage()?.resetAll()
//      expect(integration?.test_queue()).to(beEmpty())
//    }
    }
}
