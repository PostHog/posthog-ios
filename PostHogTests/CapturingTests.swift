import Quick
import Nimble
import PostHog

class CapturingTests: QuickSpec {
  override func spec() {
    var passthrough: PHGPassthroughMiddleware!
    var posthog: PHGPostHog!

    beforeEach {
      let config = PHGPostHogConfiguration(apiKey: "QUI5ydwIGeFFTa1IvCBUhxL9PyW5B0jE")
      passthrough = PHGPassthroughMiddleware()
      config.middlewares = [
        passthrough,
      ]
      posthog = PHGPostHog(configuration: config)
    }

    afterEach {
      posthog.reset()
    }

    it("handles identify:") {
      posthog.identify("testDistinctId1", properties: [
        "firstName": "Peter"
      ])
      expect(passthrough.lastContext?.eventType) == PHGEventType.identify
      let identify = passthrough.lastContext?.payload as? PHGIdentifyPayload
      expect(identify?.distinctId) == "testDistinctId1"
      expect(identify?.anonymousId).toNot(beNil())
      expect(identify?.properties?["firstName"] as? String) == "Peter"
    }

    it("handles identify with custom anonymousId:") {
      posthog.identify("testDistinctId1", properties: [
        "firstName": "Peter"
        ], options: [
          "$anon_distinct_id": "a_custom_anonymous_id"
        ])
      expect(passthrough.lastContext?.eventType) == PHGEventType.identify
      let identify = passthrough.lastContext?.payload as? PHGIdentifyPayload
      expect(identify?.distinctId) == "testDistinctId1"
      expect(identify?.anonymousId) == "a_custom_anonymous_id"
      expect(identify?.properties?["firstName"] as? String) == "Peter"
    }

    it("handles capture:") {
      posthog.capture("User Signup", properties: [
        "method": "SSO"
        ])
      expect(passthrough.lastContext?.eventType) == PHGEventType.capture
      let payload = passthrough.lastContext?.payload as? PHGCapturePayload
      expect(payload?.event) == "User Signup"
      expect(payload?.properties?["method"] as? String) == "SSO"
    }

    it("handles alias:") {
      posthog.alias("persistentDistinctId")
      expect(passthrough.lastContext?.eventType) == PHGEventType.alias
      let payload = passthrough.lastContext?.payload as? PHGAliasPayload
      expect(payload?.alias) == "persistentDistinctId"
    }

    it("handles screen:") {
      posthog.screen("Home", properties: [
        "referrer": "Google"
      ])
      expect(passthrough.lastContext?.eventType) == PHGEventType.screen
      let screen = passthrough.lastContext?.payload as? PHGScreenPayload
      expect(screen?.name) == "Home"
      expect(screen?.properties?["referrer"] as? String) == "Google"
    }
    
    it("handles group:") {
      posthog.group( "some-type", groupKey: "some-key", properties: [
        "name": "some-company-name"
        ])
      let firstContext = passthrough.allContexts[1]
      
      expect(firstContext.eventType) == PHGEventType.group
      let payload = firstContext.payload as? PHGGroupPayload
      expect(payload?.groupType) == "some-type"
      expect(payload?.properties?["name"] as? String) == "some-company-name"
    
    }

    it("handles null values") {
      posthog.capture("null test", properties: [
        "nullTest": NSNull()
        ])
      let payload = passthrough.lastContext?.payload as? PHGCapturePayload
      let isNull = (payload?.properties?["nullTest"] is NSNull)
      expect(isNull) == true
    }
  }

}
