import Quick
import Nimble
import PostHog

class PostHogTests: QuickSpec {
  override func spec() {
    let config = PHGPostHogConfiguration(apiKey: "QUI5ydwIGeFFTa1IvCBUhxL9PyW5B0jE")
    var posthog: PHGPostHog!
    var testMiddleware: TestMiddleware!
    var testApplication: TestApplication!

    beforeEach {
      testMiddleware = TestMiddleware()
      config.middlewares = [testMiddleware]
      testApplication = TestApplication()
      config.application = testApplication
      config.captureApplicationLifecycleEvents = true

      UserDefaults.standard.set("test PHGQueue should be removed", forKey: "PHGQueue")
      expect(UserDefaults.standard.string(forKey: "PHGQueue")).toNot(beNil())
      
      posthog = PHGPostHog(configuration: config)
    }

    afterEach {
      posthog.reset()
    }

    it("initialized correctly") {
      expect(posthog.configuration.flushAt) == 20
      expect(posthog.configuration.flushInterval) == 30
      expect(posthog.configuration.maxQueueSize) == 1000
      expect(posthog.configuration.apiKey) == "QUI5ydwIGeFFTa1IvCBUhxL9PyW5B0jE"
      expect(posthog.configuration.host) == URL(string: "https://app.posthog.com")
      expect(posthog.configuration.shouldUseLocationServices) == false
      expect(posthog.configuration.shouldUseBluetooth) == false
      expect(posthog.configuration.libraryName) == "posthog-ios"
      expect(posthog.configuration.libraryVersion) == PHGPostHog.version()
      expect(posthog.configuration.httpSessionDelegate).to(beNil())
      expect(posthog.getAnonymousId()).toNot(beNil())
    }

    it("initialized correctly with api host") {
      let config = PHGPostHogConfiguration(apiKey: "QUI5ydwIGeFFTa1IvCBUhxL9PyW5B0jE", host: "https://testapp.posthog.test")
      config.libraryName = "posthog-ios-test"
      config.libraryVersion = "posthog-ios-version"
      
      posthog = PHGPostHog(configuration: config)
      expect(posthog.configuration.flushAt) == 20
      expect(posthog.configuration.flushInterval) == 30
      expect(posthog.configuration.maxQueueSize) == 1000
      expect(posthog.configuration.apiKey) == "QUI5ydwIGeFFTa1IvCBUhxL9PyW5B0jE"
      expect(posthog.configuration.host) == URL(string: "https://testapp.posthog.test")
      expect(posthog.configuration.shouldUseLocationServices) == false
      expect(posthog.configuration.shouldUseBluetooth) == false
      expect(posthog.configuration.libraryVersion) == "posthog-ios-version"
      expect(posthog.configuration.libraryName) == "posthog-ios-test"
      expect(posthog.configuration.httpSessionDelegate).to(beNil())
      expect(posthog.getAnonymousId()).toNot(beNil())

      let integration = posthog.test_payloadManager()?.test_postHogIntegration()
      expect(integration!.liveContext()["$lib"] as? String) == "posthog-ios-test"
      expect(integration!.liveContext()["$lib_version"] as? String) == "posthog-ios-version"
    }

    it("clears PHGQueue from UserDefaults after initialized") {
      expect(UserDefaults.standard.string(forKey: "PHGQueue")).toEventually(beNil())
    }
    
    it("persists anonymousId") {
      let posthog2 = PHGPostHog(configuration: config)
      expect(posthog.getAnonymousId()) == posthog2.getAnonymousId()
    }

    it("persists distinctId") {
      posthog.identify("testDistinctId1")

      let posthog2 = PHGPostHog(configuration: config)

      expect(posthog.test_payloadManager()?.test_postHogIntegration()?.test_distinctId()) == "testDistinctId1"
      expect(posthog2.test_payloadManager()?.test_postHogIntegration()?.test_distinctId()) == "testDistinctId1"
    }

    it("fires Application Opened for UIApplicationDidFinishLaunching") {
      testMiddleware.swallowEvent = true
      NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidFinishLaunching, object: testApplication, userInfo: [
        UIApplication.LaunchOptionsKey.sourceApplication: "testApp",
        UIApplication.LaunchOptionsKey.url: "test://test",
      ])
    
      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
      expect(event?.event) == "Application Opened"
      expect(event?.properties?["from_background"] as? Bool) == false
      expect(event?.properties?["referring_application"] as? String) == "testApp"
      expect(event?.properties?["url"] as? String) == "test://test"
    }

    it("fires Application Opened during UIApplicationWillEnterForeground") {
      testMiddleware.swallowEvent = true
      NotificationCenter.default.post(name: NSNotification.Name.UIApplicationWillEnterForeground, object: testApplication)
      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
      expect(event?.event) == "Application Opened"
      expect(event?.properties?["from_background"] as? Bool) == true
    }
    
    it("fires Application Backgrounded during UIApplicationDidEnterBackground") {
      testMiddleware.swallowEvent = true
      NotificationCenter.default.post(name: Notification.Name.UIApplicationDidEnterBackground, object: testApplication)
      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
      expect(event?.event) == "Application Backgrounded"
    }

    it("flushes when UIApplicationDidEnterBackground is fired") {
      posthog.capture("test")
      NotificationCenter.default.post(name: Notification.Name.UIApplicationDidEnterBackground, object: testApplication)
      expect(testApplication.backgroundTasks.count).toEventually(equal(1))
      expect(testApplication.backgroundTasks[0].isEnded).toEventually(beFalse())
    }
    
    it("respects maxQueueSize") {
      let max = 72
      config.maxQueueSize = UInt(max)

      for i in 1...max * 2 {
        posthog.capture("test #\(i)")
      }

      let integration = posthog.test_payloadManager()?.test_postHogIntegration()
      expect(integration).notTo(beNil())
      
      posthog.flush()
      waitUntil(timeout: DispatchTimeInterval.seconds(60)) {done in
        let queue = DispatchQueue(label: "test")
        
        queue.async {
          while(integration?.test_queue()?.count != max) {
            sleep(1)
          }

          done()
        }
      }
    }

    it("protocol conformance should not interfere with UIApplication interface") {
      // In Xcode8/iOS10, UIApplication.h typedefs UIBackgroundTaskIdentifier as NSUInteger,
      // whereas Swift has UIBackgroundTaskIdentifier typealiaed to Int.
      // This is likely due to a custom Swift mapping for UIApplication which got out of sync.
      // If we extract the exact UIApplication method names in PHGApplicationProtocol,
      // it will cause a type mismatch between the return value from beginBackgroundTask
      // and the argument for endBackgroundTask.
      // This would impact all code in a project that imports the framework.
      // Note that this doesn't appear to be an issue any longer in Xcode9b3.
      let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
      UIApplication.shared.endBackgroundTask(task)
    }
    
    it("flushes using flushTimer") {
      let integration = posthog.test_payloadManager()?.test_postHogIntegration()

      posthog.capture("test")

      expect(integration?.test_flushTimer()).toEventuallyNot(beNil())
      expect(integration?.test_batchRequest()).to(beNil())

      integration?.test_flushTimer()?.fire()
      
      expect(integration?.test_batchRequest()).toEventuallyNot(beNil())
    }

    it("respects flushInterval") {
      let timer = posthog
        .test_payloadManager()?
        .test_postHogIntegration()?
        .test_flushTimer()
      
      expect(timer).toNot(beNil())
      expect(timer?.timeInterval) == config.flushInterval
    }
    
    it("redacts sensible URLs from deep links capturing") {
      testMiddleware.swallowEvent = true
      posthog.configuration.captureDeepLinks = true
      posthog.open(URL(string: "fb123456789://authorize#access_token=hastoberedacted")!, options: [:])
      
      
      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
      expect(event?.event) == "Deep Link Opened"
      expect(event?.properties?["url"] as? String) == "fb123456789://authorize#access_token=((redacted/fb-auth-token))"
    }

    it("redacts sensible URLs from deep links capturing using custom filters") {
      testMiddleware.swallowEvent = true
      posthog.configuration.payloadFilters["(myapp://auth\\?token=)([^&]+)"] = "$1((redacted/my-auth))"
      posthog.configuration.captureDeepLinks = true
      posthog.open(URL(string: "myapp://auth?token=hastoberedacted&other=stuff")!, options: [:])
      
      
      let event = testMiddleware.lastContext?.payload as? PHGCapturePayload
      expect(event?.event) == "Deep Link Opened"
      expect(event?.properties?["url"] as? String) == "myapp://auth?token=((redacted/my-auth))&other=stuff"
    }
    
    it("defaults PHGQueue to an empty array when missing from file storage") {
      let integration = posthog.test_payloadManager()?.test_postHogIntegration()
      expect(integration).notTo(beNil())
      integration?.test_fileStorage()?.resetAll()
      expect(integration?.test_queue()).to(beEmpty())
    }
  }
}
