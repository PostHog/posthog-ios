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
//      let config = PHGPostHogConfiguration(apiKey: "BrpS4SctoaCCsyjlnlun3OzyNJAafdlv__jUWaaJWXg")
      let config = PHGPostHogConfiguration(apiKey: "8jVz0YZ2YPtP7eL1I5l5RQIp-WcuFeD3pZO8c0YDMx4", host: "http://localhost:8000")
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
