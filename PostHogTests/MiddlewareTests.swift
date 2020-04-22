import Quick
import Nimble
import PostHog

// Changing event names and adding custom attributes
let customizeAllCaptureCalls = PHGBlockMiddleware { (context, next) in
  if context.eventType == .capture {
    next(context.modify { ctx in
      guard let capture = ctx.payload as? PHGCapturePayload else {
        return
      }
      let newEvent = "[New] \(capture.event)"
      var newProps = capture.properties ?? [:]
      newProps["customAttribute"] = "Hello"
      newProps["nullTest"] = NSNull()
      ctx.payload = PHGCapturePayload(
        event: newEvent,
        properties: newProps
      )
    })
  } else {
    next(context)
  }
}

// Simply swallows all calls and does not pass events downstream
let eatAllCalls = PHGBlockMiddleware { (context, next) in
}

class MiddlewareTests: QuickSpec {
  override func spec() {
    it("receives events") {
      let config = PHGPostHogConfiguration(apiKey: "TESTKEY")
      let passthrough = PHGPassthroughMiddleware()
      config.middlewares = [
        passthrough,
      ]
      let posthog = PHGPostHog(configuration: config)
      posthog.identify("testDistinctId1")
      expect(passthrough.lastContext?.eventType) == PHGEventType.identify
      let identify = passthrough.lastContext?.payload as? PHGIdentifyPayload
      expect(identify?.distinctId) == "testDistinctId1"
    }
    
    it("modifies and passes event to next") {
      let config = PHGPostHogConfiguration(apiKey: "TESTKEY")
      let passthrough = PHGPassthroughMiddleware()
      config.middlewares = [
        customizeAllCaptureCalls,
        passthrough,
      ]
      let posthog = PHGPostHog(configuration: config)
      posthog.capture("Purchase Success")
      expect(passthrough.lastContext?.eventType) == PHGEventType.capture
      let capture = passthrough.lastContext?.payload as? PHGCapturePayload
      expect(capture?.event) == "[New] Purchase Success"
      expect(capture?.properties?["customAttribute"] as? String) == "Hello"
      let isNull = (capture?.properties?["nullTest"] is NSNull)
      expect(isNull) == true
    }
    
    it("expects event to be swallowed if next is not called") {
      let config = PHGPostHogConfiguration(apiKey: "TESTKEY")
      let passthrough = PHGPassthroughMiddleware()
      config.middlewares = [
        eatAllCalls,
        passthrough,
      ]
      let posthog = PHGPostHog(configuration: config)
      posthog.capture("Purchase Success")
      expect(passthrough.lastContext).to(beNil())
    }
  }
}
