import Quick
import Nimble
import PostHog
import Alamofire
import Alamofire_Synchronous

// We try to make a real request to app.posthog.com and get a 200 response
class PostHogE2ETests: QuickSpec {
  override func spec() {
    var posthog: PHGPostHog!

    beforeEach {
     let config = PHGPostHogConfiguration(apiKey: "foobar")
      config.flushAt = 1

      PHGPostHog.setup(with: config)

      posthog = PHGPostHog.shared()
    }

    afterEach {
      posthog.reset()
    }

    it("capture") {
      let uuid = UUID().uuidString
      self.expectation(forNotification: NSNotification.Name("PostHogRequestDidSucceed"), object: nil, handler: nil)
      posthog.capture("E2E Test", properties: ["id": uuid])
      self.waitForExpectations(timeout: 30)
    }
  }
}
